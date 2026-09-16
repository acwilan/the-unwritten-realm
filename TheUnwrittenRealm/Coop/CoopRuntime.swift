import Foundation

public struct CoopDiceResult: Codable, Equatable, Sendable {
    public let expression: String
    public let dice: [Int]
    public let modifier: Int
    public let total: Int
    public init(expression: String, dice: [Int], modifier: Int, total: Int) { self.expression = expression; self.dice = dice; self.modifier = modifier; self.total = total }
}

public protocol CoopDiceRolling: Sendable {
    mutating func rollD20(modifier: Int) -> CoopDiceResult
}

public struct SeededCoopDice: CoopDiceRolling, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    public mutating func rollD20(modifier: Int) -> CoopDiceResult {
        state = 6364136223846793005 &* state &+ 1442695040888963407
        let value = Int((state >> 32) % 20) + 1
        return CoopDiceResult(expression: "d20", dice: [value], modifier: modifier, total: value + modifier)
    }
}

public struct ScriptedCoopDice: CoopDiceRolling, Sendable {
    private var values: [Int]
    private var index = 0
    public init(_ values: [Int]) { self.values = values }
    public mutating func rollD20(modifier: Int) -> CoopDiceResult {
        let value = min(20, max(1, values.isEmpty ? 1 : values[index % values.count])); index += 1
        return CoopDiceResult(expression: "d20", dice: [value], modifier: modifier, total: value + modifier)
    }
}

public struct CoopHostResponse: Sendable {
    public let accepted: Bool
    public let reason: String?
    public let events: [CommittedCoopEvent]
    public let projection: CoopStateProjection
    public let duplicate: Bool
    public init(accepted: Bool, reason: String? = nil, events: [CommittedCoopEvent] = [], projection: CoopStateProjection, duplicate: Bool = false) {
        self.accepted = accepted; self.reason = reason; self.events = events; self.projection = projection; self.duplicate = duplicate
    }
}

public struct CoopStateProjection: Codable, Equatable, Sendable {
    public let campaignID: CoopCampaignID
    public let revision: UInt64
    public let phase: CoopPlayPhase
    public let party: CoopPartyState
    public let world: CoopWorldState
    public let encounter: CoopEncounterState?
    public let visibleEvents: [CommittedCoopEvent]

    public init(state: CoopCampaignState, playerID: CoopPlayerID?, events: [CommittedCoopEvent] = []) {
        campaignID = state.campaignID; revision = state.revision; phase = state.phase; encounter = state.encounter
        let visibleCharacters = state.party.characters.filter { characterID, character in
            guard let playerID else { return true }
            return character.ownerID == playerID || character.sceneID == state.world.currentSceneID
        }
        party = CoopPartyState(players: state.party.players, characters: visibleCharacters,
                               playerByCharacter: state.party.playerByCharacter.filter { visibleCharacters[$0.key] != nil })
        let visibleActors = state.world.actors.filter { actor in
            actor.value.sceneID == state.world.currentSceneID || actor.value.kind == .player
        }
        world = CoopWorldState(currentSceneID: state.world.currentSceneID, scenes: state.world.scenes,
                               actors: visibleActors, facts: state.world.facts)
        visibleEvents = events.filter { $0.audience.includes(playerID) }
    }
}

public struct CoopRuntimeError: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

extension CoopRuntimeError: LocalizedError {
    public var errorDescription: String? { message }
}

/// The single serialization point for authoritative state, validation, dice, and commits.
public actor HostGameRuntime {
    private var state: CoopCampaignState
    private var dice: any CoopDiceRolling
    private let interpreter: any CoopIntentInterpreting
    private let narrator: any CoopOutcomeNarrating
    private var processedCommands: [UUID: CoopHostResponse] = [:]
    private var journal: [CommittedCoopEvent] = []
    private var nextSequence: UInt64 = 1

    public init(state: CoopCampaignState, interpreter: any CoopIntentInterpreting = DeterministicCoopInterpreter(), narrator: any CoopOutcomeNarrating = TemplateCoopNarrator(), dice: (any CoopDiceRolling)? = nil) {
        self.state = state; self.interpreter = interpreter; self.narrator = narrator; self.dice = dice ?? SeededCoopDice(seed: state.rngState)
    }

    public func snapshot() -> CoopCampaignState { state }
    public func committedEvents(after sequence: UInt64 = 0) -> [CommittedCoopEvent] { journal.filter { $0.sequence > sequence } }
    public func projection(for playerID: CoopPlayerID?) -> CoopStateProjection { CoopStateProjection(state: state, playerID: playerID) }

    public func registerPlayer(displayName: String, playerID: CoopPlayerID = UUID(), peerID: CoopPeerID) throws -> CoopPlayer {
        guard state.party.players.count < 6 else { throw CoopRuntimeError("This session already has six players.") }
        guard !state.party.players.values.contains(where: { $0.peerID == peerID }) else { throw CoopRuntimeError("This device is already in the session.") }
        _ = try commit(.playerRegistered(playerID: playerID, displayName: displayName, peerID: peerID), audience: .everyone)
        return try requirePlayer(playerID)
    }

    public func approve(playerID: CoopPlayerID, peerID: CoopPeerID) throws -> CommittedCoopEvent {
        let event = try commit(.playerApproved(playerID: playerID, peerID: peerID), audience: .everyone)
        return event
    }

    public func claimCharacter(playerID: CoopPlayerID, characterID: CoopCharacterID, commandID: UUID = UUID()) throws -> CommittedCoopEvent {
        let player = try requirePlayer(playerID)
        guard player.approved else { throw CoopRuntimeError("This player has not been approved by the host.") }
        guard state.party.characters[characterID]?.ownerID == nil else { throw CoopRuntimeError("That character is already claimed.") }
        return try commit(.characterClaimed(playerID: playerID, characterID: characterID), audience: .everyone, causedBy: commandID)
    }

    public func receive(_ submission: CoopPlayerIntentSubmission) async -> CoopHostResponse {
        if let previous = processedCommands[submission.commandID] {
            return CoopHostResponse(accepted: previous.accepted, reason: previous.reason, events: previous.events,
                                    projection: previous.projection, duplicate: true)
        }
        let projection = CoopStateProjection(state: state, playerID: submission.playerID)
        guard submission.campaignID == state.campaignID else { return remember(CoopHostResponse(accepted: false, reason: "This command belongs to another campaign.", projection: projection), id: submission.commandID) }
        guard let player = state.party.players[submission.playerID], player.approved else { return remember(CoopHostResponse(accepted: false, reason: "The host has not approved this player.", projection: projection), id: submission.commandID) }
        guard let characterID = player.characterID else { return remember(CoopHostResponse(accepted: false, reason: "Choose a character before acting.", projection: projection), id: submission.commandID) }
        guard submission.baseRevision == state.revision else { return remember(CoopHostResponse(accepted: false, reason: "Your view is out of date. Synchronize before trying again.", projection: projection), id: submission.commandID) }
        guard let scene = state.world.scenes[state.world.currentSceneID] else { return remember(CoopHostResponse(accepted: false, reason: "The current scene is missing.", projection: projection), id: submission.commandID) }
        let context = CoopVisibleContext(playerID: submission.playerID, ownActorID: characterID, scene: scene,
                                          actors: state.world.actors.values.filter { $0.sceneID == scene.id }, publicFacts: Array(state.world.facts))
        do {
            let proposal = try await interpreter.interpret(submission: submission, context: context)
            guard !proposal.needsClarification else { return remember(CoopHostResponse(accepted: false, reason: "Please clarify what you want to do.", projection: projection), id: submission.commandID) }
            var events = try resolve(proposal.command, playerID: submission.playerID, characterID: characterID, commandID: submission.commandID)
            let narrative = try await narrator.narrate(context: CoopNarrationContext(submission: submission, context: context, events: events))
            events.append(try commit(.narration(text: narrative), audience: .everyone, causedBy: submission.commandID))
            let newProjection = CoopStateProjection(state: state, playerID: submission.playerID, events: events)
            let response = CoopHostResponse(accepted: true, events: events, projection: newProjection)
            return remember(response, id: submission.commandID)
        } catch let error as CoopRuntimeError {
            return remember(CoopHostResponse(accepted: false, reason: error.message, projection: CoopStateProjection(state: state, playerID: submission.playerID)), id: submission.commandID)
        } catch {
            return remember(CoopHostResponse(accepted: false, reason: "The action could not be resolved.", projection: CoopStateProjection(state: state, playerID: submission.playerID)), id: submission.commandID)
        }
    }

    private func resolve(_ command: CoopCommand, playerID: CoopPlayerID, characterID: CoopCharacterID, commandID: UUID) throws -> [CommittedCoopEvent] {
        guard let character = state.party.characters[characterID] else { throw CoopRuntimeError("Character is missing.") }
        switch command {
        case .move(let actorID, let destination):
            guard actorID == characterID || state.world.actors[actorID] != nil else { throw CoopRuntimeError("That actor is not available.") }
            guard state.world.scenes[state.world.currentSceneID]?.exits.contains(destination) == true else { throw CoopRuntimeError("That destination is not connected to this scene.") }
            var events = [try commit(.actorMoved(actorID: actorID, sceneID: destination, zone: .nearby), audience: .everyone, causedBy: commandID)]
            if state.phase == .freePlay && state.world.actors.values.contains(where: { $0.kind == .hostile && $0.sceneID == destination && !$0.isDefeated }) {
                events.append(contentsOf: try startEncounter(causedBy: commandID))
            }
            return events
        case .attempt(let actorID, let attribute, let difficulty, let reason):
            guard actorID == characterID else { throw CoopRuntimeError("You may only control your own character.") }
            let result = dice.rollD20(modifier: character.modifier(for: attribute))
            state.rngState &+= 1
            var events = [try commit(.rollResolved(expression: result.expression, dice: result.dice, modifier: result.modifier, total: result.total, reason: reason), audience: .everyone, causedBy: commandID)]
            if result.total >= difficulty { events.append(try commit(.worldFactDiscovered(fact: "A successful (attribute.rawValue) check revealed progress."), audience: .everyone, causedBy: commandID)) }
            return events
        case .attack(let actorID, let targetID):
            guard state.phase == .initiative, state.encounter?.activeActorID == actorID else { throw CoopRuntimeError("It is not that character's turn.") }
            guard actorID == characterID, let target = state.world.actors[targetID], target.sceneID == character.sceneID else { throw CoopRuntimeError("That target cannot be attacked.") }
            let result = dice.rollD20(modifier: character.modifier(for: .might))
            var events = [try commit(.rollResolved(expression: result.expression, dice: result.dice, modifier: result.modifier, total: result.total, reason: "attack"), audience: .everyone, causedBy: commandID)]
            if result.total >= target.defense {
                events.append(try commit(.damageApplied(targetID: targetID, amount: 2), audience: .everyone, causedBy: commandID))
                if state.world.actors.values.filter({ $0.kind == .hostile && !$0.isDefeated }).isEmpty { events.append(try commit(.initiativeEnded, audience: .everyone, causedBy: commandID)) }
            }
            return events
        case .endTurn(let actorID):
            guard state.phase == .initiative, state.encounter?.activeActorID == actorID else { throw CoopRuntimeError("Only the active combatant may end the turn.") }
            guard let encounter = state.encounter, let next = encounter.entries[(encounter.activeIndex + 1) % encounter.entries.count].actorID as CoopActorID? else { throw CoopRuntimeError("The encounter has no next turn.") }
            let round = encounter.activeIndex + 1 >= encounter.entries.count ? encounter.round + 1 : encounter.round
            return [try commit(.turnEnded(actorID: actorID, nextActorID: next, round: round), audience: .everyone, causedBy: commandID)]
        }
    }

    private func commit(_ payload: CoopGameEvent, audience: CoopEventAudience, causedBy: UUID? = nil) throws -> CommittedCoopEvent {
        let event = CommittedCoopEvent(sequence: nextSequence, causedBy: causedBy, audience: audience, payload: payload)
        state = try state.reduced(by: payload); journal.append(event); nextSequence += 1; return event
    }

    private func startEncounter(causedBy: UUID) throws -> [CommittedCoopEvent] {
        let actorIDs = state.world.actors.values.filter { $0.sceneID == state.world.currentSceneID && !$0.isDefeated && ($0.kind == .player || $0.kind == .hostile) }.map(\.id)
        guard !actorIDs.isEmpty else { throw CoopRuntimeError("The encounter has no combatants.") }
        var entries: [InitiativeEntry] = []
        var events: [CommittedCoopEvent] = []
        for actorID in actorIDs {
            let result = dice.rollD20(modifier: 0)
            entries.append(InitiativeEntry(actorID: actorID, total: result.total))
            events.append(try commit(.rollResolved(expression: result.expression, dice: result.dice, modifier: result.modifier, total: result.total, reason: "initiative"), audience: .everyone, causedBy: causedBy))
        }
        entries.sort { $0.total == $1.total ? $0.actorID.uuidString < $1.actorID.uuidString : $0.total > $1.total }
        events.append(try commit(.initiativeStarted(entries: entries), audience: .everyone, causedBy: causedBy))
        return events
    }

    private func requirePlayer(_ id: CoopPlayerID) throws -> CoopPlayer { guard let player = state.party.players[id] else { throw CoopRuntimeError("Unknown player.") }; return player }
    private func remember(_ response: CoopHostResponse, id: UUID) -> CoopHostResponse { processedCommands[id] = response; return response }
}

public struct DeterministicCoopInterpreter: CoopIntentInterpreting {
    public init() {}
    public func interpret(submission: CoopPlayerIntentSubmission, context: CoopVisibleContext) async throws -> CoopActionProposal {
        let text = submission.text.lowercased()
        let ownActor = context.ownActorID ?? context.actors.first(where: { $0.kind == .player })?.id ?? UUID()
        if text.contains("end turn") || text == "done" { return CoopActionProposal(command: .endTurn(actorID: ownActor)) }
        if text.contains("attack") || text.contains("fight") {
            guard let target = context.actors.first(where: { $0.kind == .hostile }) else { return CoopActionProposal(command: .attempt(actorID: ownActor, attribute: .might, difficulty: 10, reason: "attack"), confidence: 0.6) }
            return CoopActionProposal(command: .attack(actorID: ownActor, targetID: target.id))
        }
        if let destination = context.scene.exits.first(where: { text.contains($0.replacingOccurrences(of: "_", with: " ")) }) {
            return CoopActionProposal(command: .move(actorID: ownActor, destination: destination))
        }
        let attribute: CoopAttribute = text.contains("convince") || text.contains("persuade") ? .presence : (text.contains("look") || text.contains("inspect") ? .insight : .finesse)
        return CoopActionProposal(command: .attempt(actorID: ownActor, attribute: attribute, difficulty: 11, reason: submission.text))
    }
}

/// Adapts the existing Foundation Models-backed application service to the
/// co-op proposal boundary. The adapter only converts prose into a proposal;
/// the host runtime still validates targets, turns, rolls, and state changes.
public struct AIProviderCoopInterpreter: CoopIntentInterpreting {
    private let provider: any AIProvider
    public init(provider: any AIProvider) { self.provider = provider }

    public func interpret(submission: CoopPlayerIntentSubmission, context: CoopVisibleContext) async throws -> CoopActionProposal {
        let location = Location(id: context.scene.id, name: context.scene.name, description: context.scene.description, exits: context.scene.exits, npcIDs: [])
        let player = PlayerCharacter(name: "Co-op player", level: 1, hitPoints: 10, maxHitPoints: 10, attributes: [.might: 10, .finesse: 10, .insight: 10, .presence: 10], inventory: [])
        let dmContext = DMContext(location: location, player: player, nearbyNPCs: [], activeQuest: nil, relevantFacts: context.publicFacts, recentConversation: [])
        let action = try await provider.interpret(command: PlayerCommand(id: submission.commandID, rawText: submission.text), context: dmContext)
        let actorID = context.ownActorID ?? context.actors.first(where: { $0.kind == .player })?.id ?? UUID()
        if action.intent == .travel, let destination = action.destinationID { return CoopActionProposal(command: .move(actorID: actorID, destination: destination)) }
        if action.intent == .attack, let target = action.targetID, let targetID = UUID(uuidString: target) { return CoopActionProposal(command: .attack(actorID: actorID, targetID: targetID)) }
        let attribute: CoopAttribute = action.intent == .persuade || action.intent == .social || action.intent == .deceive ? .presence : (action.intent == .investigate || action.intent == .explore ? .insight : .finesse)
        return CoopActionProposal(command: .attempt(actorID: actorID, attribute: attribute, difficulty: 11, reason: action.approach))
    }
}

public struct FallbackCoopInterpreter: CoopIntentInterpreting {
    private let primary: any CoopIntentInterpreting
    private let fallback: any CoopIntentInterpreting
    public init(primary: any CoopIntentInterpreting, fallback: any CoopIntentInterpreting) { self.primary = primary; self.fallback = fallback }
    public func interpret(submission: CoopPlayerIntentSubmission, context: CoopVisibleContext) async throws -> CoopActionProposal {
        do { return try await primary.interpret(submission: submission, context: context) }
        catch { return try await fallback.interpret(submission: submission, context: context) }
    }
}

public struct TemplateCoopNarrator: CoopOutcomeNarrating {
    public init() {}
    public func narrate(context: CoopNarrationContext) async throws -> String {
        let scene = context.context.scene.name
        if let event = context.events.last(where: { if case .rollResolved = $0.payload { return true }; return false }) {
            if case .rollResolved(_, _, _, let total, let reason) = event.payload { return "In \(scene), the party's \(reason) resolves with a total of \(total)." }
        }
        if let movement = context.events.first(where: { if case .actorMoved = $0.payload { return true }; return false }), case .actorMoved(_, let destination, _) = movement.payload { return "The party leaves \(scene) and moves toward \(destination)." }
        return "The party's choice changes the situation in \(scene)."
    }
}

public struct AIProviderCoopNarrator: CoopOutcomeNarrating {
    private let provider: any AIProvider
    public init(provider: any AIProvider) { self.provider = provider }
    public func narrate(context: CoopNarrationContext) async throws -> String {
        let location = Location(id: context.context.scene.id, name: context.context.scene.name, description: context.context.scene.description, exits: context.context.scene.exits, npcIDs: [])
        let player = PlayerCharacter(name: "Co-op party", level: 1, hitPoints: 10, maxHitPoints: 10, attributes: [.might: 10, .finesse: 10, .insight: 10, .presence: 10], inventory: [])
        let dm = DMContext(location: location, player: player, nearbyNPCs: [], activeQuest: nil, relevantFacts: context.context.publicFacts, recentConversation: [])
        let action = InterpretedAction(intent: .explore, approach: context.submission.text, desiredOutcome: "resolve the party's intention")
        let resolution = ActionResolution(isValid: true, explanation: context.events.map { event in
            if case .narration = event.payload { return "" }; return String(describing: event.payload)
        }.joined(separator: " "), targetNPCID: nil)
        return try await provider.narrate(context: NarrationContext(dm: dm, command: PlayerCommand(id: context.submission.commandID, rawText: context.submission.text), action: action, resolution: resolution, events: []))
    }
}

public struct FallbackCoopNarrator: CoopOutcomeNarrating {
    private let primary: any CoopOutcomeNarrating
    private let fallback: any CoopOutcomeNarrating
    public init(primary: any CoopOutcomeNarrating, fallback: any CoopOutcomeNarrating) { self.primary = primary; self.fallback = fallback }
    public func narrate(context: CoopNarrationContext) async throws -> String {
        do { return try await primary.narrate(context: context) }
        catch { return try await fallback.narrate(context: context) }
    }
}
