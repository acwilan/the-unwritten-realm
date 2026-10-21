import Foundation

public enum CheckOutcome: String, Codable, Sendable { case criticalFailure, failure, success, criticalSuccess }

public struct SkillCheck: Codable, Equatable, Sendable {
    public let attribute: Attribute
    public let roll: Int
    public let modifier: Int
    public let difficulty: Int
    public let total: Int
    public let outcome: CheckOutcome

    public var label: String { "d20 \(roll) + \(modifier) = \(total) vs. \(difficulty)" }

    public func label(in language: AppLanguage) -> String { label }
}

public protocol RandomSource: Sendable {
    mutating func nextInt(in range: ClosedRange<Int>) -> Int
}

public struct SystemRandomSource: RandomSource {
    public init() {}
    public mutating func nextInt(in range: ClosedRange<Int>) -> Int { Int.random(in: range) }
}

public struct SequenceRandomSource: RandomSource {
    private var values: [Int]
    private var index = 0
    public init(_ values: [Int]) { self.values = values }
    public mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        guard !values.isEmpty else { return range.lowerBound }
        let value = values[index % values.count]
        index += 1
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

public struct ActionResolution: Equatable, Sendable {
    public let isValid: Bool
    public let check: SkillCheck?
    public let events: [GameEvent]
    public let explanation: String
    public let targetNPCID: String?

    public init(isValid: Bool, check: SkillCheck? = nil, events: [GameEvent] = [], explanation: String, targetNPCID: String? = nil) {
        self.isValid = isValid
        self.check = check
        self.events = events
        self.explanation = explanation
        self.targetNPCID = targetNPCID
    }
}

public struct RulesEngine: Sendable {
    public init() {}

    public mutating func resolve(_ action: InterpretedAction, in state: CampaignState, random: inout any RandomSource) -> ActionResolution {
        let language = state.language
        switch action.intent {
        case .travel:
            guard let destinationID = action.destinationID, state.locations[state.currentLocationID]?.exits.contains(destinationID) == true,
                  let destination = state.locations[destinationID] else {
                return ActionResolution(isValid: false, explanation: AppLocalization.string("That destination is not reachable from here.", language: language))
            }
            return ActionResolution(isValid: true, events: [
                GameEvent(kind: .locationChanged, targetID: destination.id, text: destination.name),
                GameEvent(kind: .timeAdvanced, value: 10)
            ], explanation: AppLocalization.format("You travel to %@.", language: language, destination.name))

        case .useItem:
            guard let name = action.referencedItemName,
                  let item = state.player.inventory.first(where: { $0.name.localizedCaseInsensitiveContains(name) || $0.id == name }) else {
                return ActionResolution(isValid: false, explanation: AppLocalization.format("You do not have %@.", language: language, action.referencedItemName ?? AppLocalization.string("that item", language: language)))
            }
            guard item.usable else { return ActionResolution(isValid: false, explanation: AppLocalization.string("That item cannot be used in that way.", language: language)) }
            let heal = item.id.contains("potion") ? 5 : 0
            var events = [GameEvent(kind: .itemRemoved, targetID: item.id, text: item.name)]
            if heal > 0 { events.append(GameEvent(kind: .characterHealed, value: heal)) }
            return ActionResolution(isValid: true, events: events, explanation: AppLocalization.format("You use the %@.", language: language, item.name))

        case .rest:
            return ActionResolution(isValid: true, events: [GameEvent(kind: .characterHealed, value: 2), GameEvent(kind: .timeAdvanced, value: 30)], explanation: AppLocalization.string("You take a brief rest.", language: language))

        case .unknown:
            return ActionResolution(isValid: false, explanation: AppLocalization.string("I’m not sure how to resolve that as an action yet. Try describing a conversation, investigation, journey, item use, or risky attempt.", language: language))

        case .explore, .social, .deceive, .persuade, .investigate, .attack, .help:
            return resolveCheck(action, in: state, random: &random)
        }
    }

    private func resolveCheck(_ action: InterpretedAction, in state: CampaignState, random: inout any RandomSource) -> ActionResolution {
        let target = findNPC(for: action, in: state)
        let attribute: Attribute
        let difficulty: Int
        switch action.intent {
        case .deceive: attribute = .presence; difficulty = 12
        case .persuade, .social, .help: attribute = .presence; difficulty = 11
        case .investigate, .explore: attribute = .insight; difficulty = 12
        case .attack: attribute = .might; difficulty = 12
        default: attribute = .finesse; difficulty = 10
        }
        let targetDifficulty = state.difficulty.adjustedTarget(difficulty)
        let roll = random.nextInt(in: 1...20)
        let modifier = state.player.modifier(for: attribute)
        let total = roll + modifier
        let outcome: CheckOutcome = roll == 1 ? .criticalFailure : roll == 20 ? .criticalSuccess : total >= targetDifficulty ? .success : .failure
        let check = SkillCheck(attribute: attribute, roll: roll, modifier: modifier, difficulty: targetDifficulty, total: total, outcome: outcome)
        let language = state.language
        let outcomeText = AppLocalization.string(outcome.rawValue, language: language)
        var events = [GameEvent(kind: .skillCheckResolved, value: total, text: AppLocalization.format("%@ check: %@ — %@.", language: language, attribute.localizedDisplayName(in: language), check.label, outcomeText))]
        var explanation = check.outcome == .success || check.outcome == .criticalSuccess
            ? AppLocalization.string("The attempt works.", language: language)
            : AppLocalization.string("The attempt falls short.", language: language)
        switch (action.intent, outcome) {
        case (.attack, .success), (.attack, .criticalSuccess): events.append(GameEvent(kind: .characterDamaged, value: outcome == .criticalSuccess ? 1 : 2, text: AppLocalization.string("The danger bites back.", language: language)))
            explanation = AppLocalization.string("Your attack lands, but the danger bites back.", language: language)
        case (.deceive, .success), (.deceive, .criticalSuccess):
            if let target {
                events.append(GameEvent(kind: .npcDispositionChanged, targetID: target.id, value: 8, text: AppLocalization.format("%@ seems more receptive.", language: language, target.name)))
                explanation = AppLocalization.format("%@ seems to believe you.", language: language, target.name)
            }
        case (.persuade, .success), (.persuade, .criticalSuccess), (.social, .success), (.social, .criticalSuccess):
            if let target {
                events.append(GameEvent(kind: .npcDispositionChanged, targetID: target.id, value: 8, text: AppLocalization.format("%@ seems more receptive.", language: language, target.name)))
                if let fact = target.knownFacts.first(where: { !state.discoveredFacts.contains($0) }) {
                    events.append(GameEvent(kind: .factDiscovered, text: fact))
                    explanation = AppLocalization.format("%@ opens up: %@", language: language, target.name, fact)
                } else {
                    explanation = AppLocalization.format("%@ seems more receptive.", language: language, target.name)
                }
            }
        case (.investigate, .success), (.investigate, .criticalSuccess), (.explore, .success), (.explore, .criticalSuccess):
            if let clue = locationClue(for: state), !state.discoveredFacts.contains(clue) {
                events.append(GameEvent(kind: .factDiscovered, text: clue))
                explanation = AppLocalization.format("You uncover a clue: %@", language: language, clue)
            } else {
                explanation = AppLocalization.string("You find no new clue, but your understanding of the area sharpens.", language: language)
            }
        case (.help, .success), (.help, .criticalSuccess):
            events.append(GameEvent(kind: .factDiscovered, text: AppLocalization.string("The immediate problem has a workable weakness.", language: language)))
            explanation = AppLocalization.string("You identify a workable weakness in the immediate problem.", language: language)
        default: break
        }
        return ActionResolution(isValid: true, check: check, events: events, explanation: explanation, targetNPCID: target?.id)
    }

    private func locationClue(for state: CampaignState) -> String? {
        let l = { (key: String) in AppLocalization.string(key, language: state.language) }
        switch state.currentLocationID {
        case "tavern": return l("Mira's map marks the Old Road as a route toward the Sunken Vault.")
        case "square": return l("The watch post confirms that the Old Road leads toward the ruined chapel.")
        case "blacksmith": return l("The chapel altar has a hidden mechanism.")
        case "old_road": return l("The broken milestones point toward a chapel swallowed by ivy.")
        case "chapel": return l("The empty reliquary bears the same crescent mark as the old silver coin.")
        case "forest_path": return l("The forest path leads to a guarded rope bridge.")
        case "goblin_bridge": return l("The ravine route can reach the Sunken Vault.")
        case "dungeon": return l("The duke's seal is carved into the vault door.")
        default: return nil
        }
    }

    private func findNPC(for action: InterpretedAction, in state: CampaignState) -> NPC? {
        let ids = state.locations[state.currentLocationID]?.npcIDs ?? []
        return ids.compactMap { state.npcs[$0] }.first { npc in
            action.targetID == npc.id || action.targetName.map { npc.name.localizedCaseInsensitiveContains($0) } == true
        } ?? ids.compactMap { state.npcs[$0] }.first
    }
}
