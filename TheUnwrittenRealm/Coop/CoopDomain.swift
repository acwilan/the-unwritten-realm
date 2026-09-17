import Foundation

// The MVP remains a single Xcode target, but these types form the transport- and
// UI-independent seams described in the architecture brief. The `Coop` prefix
// avoids colliding with the original single-player prototype while migration is
// incremental.

public typealias CoopCampaignID = UUID
public typealias CoopPlayerID = UUID
public typealias CoopCharacterID = UUID
public typealias CoopActorID = UUID
public typealias CoopSceneID = String
public typealias CoopEntityID = String
public typealias CoopPeerID = String

public enum CoopPlayPhase: String, Codable, Sendable {
    case freePlay
    case initiative
    case paused
}

public enum RelativeZone: String, Codable, Sendable, CaseIterable {
    case engaged
    case nearby
    case distant
    case outOfScene
}

public struct CoopPlayer: Codable, Equatable, Sendable, Identifiable {
    public let id: CoopPlayerID
    public var displayName: String
    public var peerID: CoopPeerID?
    public var approved: Bool
    public var characterID: CoopCharacterID?

    public init(id: CoopPlayerID = UUID(), displayName: String, peerID: CoopPeerID? = nil,
                approved: Bool = true, characterID: CoopCharacterID? = nil) {
        self.id = id
        self.displayName = displayName
        self.peerID = peerID
        self.approved = approved
        self.characterID = characterID
    }
}

public struct CoopCharacter: Codable, Equatable, Sendable, Identifiable {
    public let id: CoopCharacterID
    public var name: String
    public var ownerID: CoopPlayerID?
    public var sceneID: CoopSceneID
    public var zone: RelativeZone
    public var hitPoints: Int
    public var maxHitPoints: Int
    public var defense: Int
    public var might: Int
    public var finesse: Int
    public var insight: Int
    public var presence: Int
    public var inventory: [String]

    public init(id: CoopCharacterID = UUID(), name: String, ownerID: CoopPlayerID? = nil,
                sceneID: CoopSceneID, zone: RelativeZone = .nearby, hitPoints: Int = 10,
                maxHitPoints: Int = 10, defense: Int = 10, might: Int = 10, finesse: Int = 10,
                insight: Int = 10, presence: Int = 10, inventory: [String] = []) {
        self.id = id; self.name = name; self.ownerID = ownerID; self.sceneID = sceneID
        self.zone = zone; self.hitPoints = hitPoints; self.maxHitPoints = maxHitPoints
        self.defense = defense; self.might = might; self.finesse = finesse; self.insight = insight
        self.presence = presence; self.inventory = inventory
    }

    public func modifier(for attribute: CoopAttribute) -> Int {
        let score: Int
        switch attribute {
        case .might: score = might
        case .finesse: score = finesse
        case .insight: score = insight
        case .presence: score = presence
        }
        return (score - 10) / 2
    }
}

public enum CoopAttribute: String, Codable, Sendable { case might, finesse, insight, presence }

public enum CoopActorKind: String, Codable, Sendable { case player, npc, hostile }

public struct CoopActor: Codable, Equatable, Sendable, Identifiable {
    public let id: CoopActorID
    public var name: String
    public var kind: CoopActorKind
    public var sceneID: CoopSceneID
    public var zone: RelativeZone
    public var hitPoints: Int
    public var maxHitPoints: Int
    public var defense: Int
    public var isDefeated: Bool

    public init(id: CoopActorID = UUID(), name: String, kind: CoopActorKind, sceneID: CoopSceneID,
                zone: RelativeZone = .nearby, hitPoints: Int = 6, maxHitPoints: Int = 6,
                defense: Int = 10, isDefeated: Bool = false) {
        self.id = id; self.name = name; self.kind = kind; self.sceneID = sceneID
        self.zone = zone; self.hitPoints = hitPoints; self.maxHitPoints = maxHitPoints
        self.defense = defense; self.isDefeated = isDefeated
    }
}

public struct CoopScene: Codable, Equatable, Sendable, Identifiable {
    public let id: CoopSceneID
    public let name: String
    public let description: String
    public let exits: [CoopSceneID]
    public let landmarks: [String]

    public init(id: CoopSceneID, name: String, description: String, exits: [CoopSceneID] = [], landmarks: [String] = []) {
        self.id = id; self.name = name; self.description = description; self.exits = exits; self.landmarks = landmarks
    }
}

public struct CoopPartyState: Codable, Equatable, Sendable {
    public var players: [CoopPlayerID: CoopPlayer]
    public var characters: [CoopCharacterID: CoopCharacter]
    public var playerByCharacter: [CoopCharacterID: CoopPlayerID]

    public init(players: [CoopPlayerID: CoopPlayer] = [:], characters: [CoopCharacterID: CoopCharacter] = [:], playerByCharacter: [CoopCharacterID: CoopPlayerID] = [:]) {
        self.players = players; self.characters = characters; self.playerByCharacter = playerByCharacter
    }
}

public struct CoopWorldState: Codable, Equatable, Sendable {
    public var currentSceneID: CoopSceneID
    public var scenes: [CoopSceneID: CoopScene]
    public var actors: [CoopActorID: CoopActor]
    public var facts: Set<String>

    public init(currentSceneID: CoopSceneID, scenes: [CoopSceneID: CoopScene], actors: [CoopActorID: CoopActor] = [:], facts: Set<String> = []) {
        self.currentSceneID = currentSceneID; self.scenes = scenes; self.actors = actors; self.facts = facts
    }
}

public struct InitiativeEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let actorID: CoopActorID
    public let total: Int
    public init(id: UUID = UUID(), actorID: CoopActorID, total: Int) { self.id = id; self.actorID = actorID; self.total = total }
}

public struct CoopEncounterState: Codable, Equatable, Sendable {
    public var encounterID: UUID
    public var entries: [InitiativeEntry]
    public var round: Int
    public var activeIndex: Int

    public init(encounterID: UUID = UUID(), entries: [InitiativeEntry], round: Int = 1, activeIndex: Int = 0) {
        self.encounterID = encounterID; self.entries = entries; self.round = round; self.activeIndex = activeIndex
    }

    public var activeActorID: CoopActorID? { entries.indices.contains(activeIndex) ? entries[activeIndex].actorID : nil }
}

public struct CoopCampaignState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public var schemaVersion: Int
    public let campaignID: CoopCampaignID
    public var difficulty: CampaignDifficulty
    public var revision: UInt64
    public var phase: CoopPlayPhase
    public var party: CoopPartyState
    public var world: CoopWorldState
    public var encounter: CoopEncounterState?
    public var quests: [String: String]
    public var rngState: UInt64

    public init(campaignID: CoopCampaignID = UUID(), revision: UInt64 = 0, phase: CoopPlayPhase = .freePlay,
                difficulty: CampaignDifficulty = .easy,
                party: CoopPartyState, world: CoopWorldState, encounter: CoopEncounterState? = nil,
                quests: [String: String] = [:], rngState: UInt64 = 0x9E3779B97F4A7C15, schemaVersion: Int = currentSchemaVersion) {
        self.schemaVersion = schemaVersion; self.campaignID = campaignID; self.difficulty = difficulty; self.revision = revision; self.phase = phase
        self.party = party; self.world = world; self.encounter = encounter; self.quests = quests; self.rngState = rngState
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, campaignID, difficulty, revision, phase, party, world, encounter, quests, rngState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = max(try container.decode(Int.self, forKey: .schemaVersion), CoopCampaignState.currentSchemaVersion)
        campaignID = try container.decode(CoopCampaignID.self, forKey: .campaignID)
        difficulty = try container.decodeIfPresent(CampaignDifficulty.self, forKey: .difficulty) ?? .easy
        revision = try container.decode(UInt64.self, forKey: .revision)
        phase = try container.decode(CoopPlayPhase.self, forKey: .phase)
        party = try container.decode(CoopPartyState.self, forKey: .party)
        world = try container.decode(CoopWorldState.self, forKey: .world)
        encounter = try container.decodeIfPresent(CoopEncounterState.self, forKey: .encounter)
        quests = try container.decode([String: String].self, forKey: .quests)
        rngState = try container.decode(UInt64.self, forKey: .rngState)
    }
}

public enum CoopEventAudience: Codable, Equatable, Sendable {
    case everyone
    case players(Set<CoopPlayerID>)
    case hostOnly

    public func includes(_ playerID: CoopPlayerID?) -> Bool {
        switch self { case .everyone: return true; case .hostOnly: return playerID == nil; case .players(let ids): return playerID.map(ids.contains) ?? false }
    }
}

public enum CoopGameEvent: Codable, Equatable, Sendable {
    case playerIntent(playerID: CoopPlayerID, text: String)
    case playerRegistered(playerID: CoopPlayerID, displayName: String, peerID: CoopPeerID)
    case playerApproved(playerID: CoopPlayerID, peerID: CoopPeerID)
    case characterClaimed(playerID: CoopPlayerID, characterID: CoopCharacterID)
    case actorMoved(actorID: CoopActorID, sceneID: CoopSceneID, zone: RelativeZone)
    case rollResolved(expression: String, dice: [Int], modifier: Int, total: Int, reason: String)
    case damageApplied(targetID: CoopActorID, amount: Int)
    case healingApplied(targetID: CoopActorID, amount: Int)
    case initiativeStarted(entries: [InitiativeEntry])
    case turnEnded(actorID: CoopActorID, nextActorID: CoopActorID?, round: Int)
    case initiativeEnded
    case worldFactDiscovered(fact: String)
    case narration(text: String)
    case privateObservation(text: String, playerID: CoopPlayerID)
}

public struct CommittedCoopEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sequence: UInt64
    public let causedBy: UUID?
    public let audience: CoopEventAudience
    public let payload: CoopGameEvent

    public init(id: UUID = UUID(), sequence: UInt64, causedBy: UUID? = nil, audience: CoopEventAudience = .everyone, payload: CoopGameEvent) {
        self.id = id; self.sequence = sequence; self.causedBy = causedBy; self.audience = audience; self.payload = payload
    }
}

public enum CoopReducerError: Error, Equatable, Sendable {
    case invalidEvent(String)
    case unknownActor
    case unknownScene
    case invalidTurn
}

extension CoopReducerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidEvent(let message): return message
        case .unknownActor: return "The requested actor is missing from the campaign."
        case .unknownScene: return "The requested scene is missing from the campaign."
        case .invalidTurn: return "That action is not valid for the current turn."
        }
    }
}

public extension CoopCampaignState {
    /// Pure canonical transition. Host validation happens before this function.
    func reduced(by event: CoopGameEvent) throws -> CoopCampaignState {
        var next = self
        switch event {
        case .playerIntent: break
        case .playerRegistered(let playerID, let displayName, let peerID):
            guard next.party.players[playerID] == nil else { throw CoopReducerError.invalidEvent("Player is already registered") }
            next.party.players[playerID] = CoopPlayer(id: playerID, displayName: displayName, peerID: peerID, approved: false)
        case .playerApproved(let playerID, let peerID):
            guard var player = next.party.players[playerID] else { throw CoopReducerError.invalidEvent("Unknown player") }
            player.approved = true; player.peerID = peerID; next.party.players[playerID] = player
        case .characterClaimed(let playerID, let characterID):
            guard var player = next.party.players[playerID], var character = next.party.characters[characterID] else { throw CoopReducerError.invalidEvent("Unknown claim") }
            guard character.ownerID == nil, player.characterID == nil else { throw CoopReducerError.invalidEvent("Character is already claimed") }
            character.ownerID = playerID; player.characterID = characterID
            next.party.characters[characterID] = character; next.party.players[playerID] = player; next.party.playerByCharacter[characterID] = playerID
        case .actorMoved(let actorID, let sceneID, let zone):
            guard var actor = next.world.actors[actorID] else { throw CoopReducerError.unknownActor }
            guard next.world.scenes[sceneID] != nil else { throw CoopReducerError.unknownScene }
            actor.sceneID = sceneID; actor.zone = zone; next.world.actors[actorID] = actor
            if actor.kind == .player {
                next.world.currentSceneID = sceneID
                if var character = next.party.characters[actorID] { character.sceneID = sceneID; character.zone = zone; next.party.characters[actorID] = character }
            }
        case .rollResolved: break
        case .damageApplied(let targetID, let amount):
            guard var actor = next.world.actors[targetID] else { throw CoopReducerError.unknownActor }
            actor.hitPoints = max(0, actor.hitPoints - max(0, amount)); actor.isDefeated = actor.hitPoints == 0; next.world.actors[targetID] = actor
        case .healingApplied(let targetID, let amount):
            guard var actor = next.world.actors[targetID] else { throw CoopReducerError.unknownActor }
            actor.hitPoints = min(actor.maxHitPoints, actor.hitPoints + max(0, amount)); next.world.actors[targetID] = actor
        case .initiativeStarted(let entries):
            guard !entries.isEmpty else { throw CoopReducerError.invalidEvent("Initiative cannot be empty") }
            next.phase = .initiative; next.encounter = CoopEncounterState(entries: entries)
        case .turnEnded(let actorID, _, let round):
            guard var encounter = next.encounter, encounter.activeActorID == actorID else { throw CoopReducerError.invalidTurn }
            encounter.activeIndex = encounter.activeIndex + 1
            if encounter.activeIndex >= encounter.entries.count { encounter.activeIndex = 0 }
            encounter.round = round; next.encounter = encounter
        case .initiativeEnded: next.phase = .freePlay; next.encounter = nil
        case .worldFactDiscovered(let fact): next.world.facts.insert(fact)
        case .narration, .privateObservation: break
        }
        next.revision += 1
        return next
    }
}

public struct CoopPlayerIntentSubmission: Codable, Equatable, Sendable {
    public let commandID: UUID
    public let campaignID: CoopCampaignID
    public let playerID: CoopPlayerID
    public let baseRevision: UInt64
    public let text: String

    public init(commandID: UUID = UUID(), campaignID: CoopCampaignID, playerID: CoopPlayerID, baseRevision: UInt64, text: String) {
        self.commandID = commandID; self.campaignID = campaignID; self.playerID = playerID; self.baseRevision = baseRevision; self.text = text
    }
}

public enum CoopCommand: Codable, Equatable, Sendable {
    case move(actorID: CoopActorID, destination: CoopSceneID)
    case attack(actorID: CoopActorID, targetID: CoopActorID)
    case endTurn(actorID: CoopActorID)
    case attempt(actorID: CoopActorID, attribute: CoopAttribute, difficulty: Int, reason: String)
}

public struct CoopActionProposal: Codable, Equatable, Sendable {
    public let command: CoopCommand
    public let confidence: Double
    public let needsClarification: Bool
    public init(command: CoopCommand, confidence: Double = 1, needsClarification: Bool = false) { self.command = command; self.confidence = confidence; self.needsClarification = needsClarification }
}

public struct CoopVisibleContext: Sendable {
    public let playerID: CoopPlayerID
    public let ownActorID: CoopActorID?
    public let scene: CoopScene
    public let actors: [CoopActor]
    public let publicFacts: [String]
    public init(playerID: CoopPlayerID, ownActorID: CoopActorID? = nil, scene: CoopScene, actors: [CoopActor], publicFacts: [String]) {
        self.playerID = playerID; self.ownActorID = ownActorID; self.scene = scene; self.actors = actors; self.publicFacts = publicFacts
    }
}

public protocol CoopIntentInterpreting: Sendable {
    func interpret(submission: CoopPlayerIntentSubmission, context: CoopVisibleContext) async throws -> CoopActionProposal
}

public struct CoopNarrationContext: Sendable {
    public let submission: CoopPlayerIntentSubmission
    public let context: CoopVisibleContext
    public let events: [CommittedCoopEvent]
    public init(submission: CoopPlayerIntentSubmission, context: CoopVisibleContext, events: [CommittedCoopEvent]) { self.submission = submission; self.context = context; self.events = events }
}

public protocol CoopOutcomeNarrating: Sendable {
    func narrate(context: CoopNarrationContext) async throws -> String
}
