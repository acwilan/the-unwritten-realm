import Foundation

public enum GameEventKind: String, Codable, Sendable {
    case skillCheckResolved
    case itemAdded
    case itemRemoved
    case characterDamaged
    case characterHealed
    case npcDispositionChanged
    case locationChanged
    case factDiscovered
    case questStateChanged
    case timeAdvanced
}

public struct GameEvent: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: GameEventKind
    public let targetID: String?
    public let value: Int?
    public let text: String?

    public init(id: UUID = UUID(), kind: GameEventKind, targetID: String? = nil, value: Int? = nil, text: String? = nil) {
        self.id = id
        self.kind = kind
        self.targetID = targetID
        self.value = value
        self.text = text
    }

    public var summary: String {
        switch kind {
        case .skillCheckResolved: return text ?? "A check was resolved."
        case .itemAdded: return "Gained \(text ?? "an item")."
        case .itemRemoved: return "Used \(text ?? "an item")."
        case .characterDamaged: return "Lost \(value ?? 0) hit points."
        case .characterHealed: return "Recovered \(value ?? 0) hit points."
        case .npcDispositionChanged: return "\(text ?? "An NPC's attitude changed.")"
        case .locationChanged: return "Moved to \(text ?? "a new location")."
        case .factDiscovered: return "Discovered: \(text ?? "a new fact")."
        case .questStateChanged: return text ?? "Quest progress changed."
        case .timeAdvanced: return "Time passed."
        }
    }

    public func summary(in language: AppLanguage) -> String {
        switch kind {
        case .skillCheckResolved: return text ?? AppLocalization.string("A check was resolved.", language: language)
        case .itemAdded: return AppLocalization.format("Gained %@.", language: language, text ?? AppLocalization.string("an item", language: language))
        case .itemRemoved: return AppLocalization.format("Used %@.", language: language, text ?? AppLocalization.string("an item", language: language))
        case .characterDamaged: return AppLocalization.format("Lost %@ hit points.", language: language, String(value ?? 0))
        case .characterHealed: return AppLocalization.format("Recovered %@ hit points.", language: language, String(value ?? 0))
        case .npcDispositionChanged: return text ?? AppLocalization.string("An NPC's attitude changed.", language: language)
        case .locationChanged: return AppLocalization.format("Moved to %@.", language: language, text ?? AppLocalization.string("a new location", language: language))
        case .factDiscovered: return AppLocalization.format("Discovered: %@", language: language, text ?? AppLocalization.string("a new fact", language: language))
        case .questStateChanged: return text ?? AppLocalization.string("Quest progress changed.", language: language)
        case .timeAdvanced: return AppLocalization.string("Time passed.", language: language)
        }
    }
}

public extension CampaignState {
    mutating func apply(_ event: GameEvent) {
        switch event.kind {
        case .skillCheckResolved:
            break
        case .itemAdded:
            if let itemID = event.targetID, !player.inventory.contains(where: { $0.id == itemID }) {
                player.inventory.append(Item(id: itemID, name: event.text ?? itemID, description: "A campaign item."))
            }
        case .itemRemoved:
            if let itemID = event.targetID {
                player.inventory.removeAll { $0.id == itemID }
            }
        case .characterDamaged:
            player.hitPoints = max(0, player.hitPoints - (event.value ?? 0))
        case .characterHealed:
            player.hitPoints = min(player.maxHitPoints, player.hitPoints + (event.value ?? 0))
        case .npcDispositionChanged:
            if let targetID = event.targetID, var npc = npcs[targetID] {
                npc.disposition = max(-100, min(100, npc.disposition + (event.value ?? 0)))
                npcs[targetID] = npc
            }
        case .locationChanged:
            if let targetID = event.targetID, locations[targetID] != nil {
                currentLocationID = targetID
            }
        case .factDiscovered:
            if let fact = event.text, !discoveredFacts.contains(fact) { discoveredFacts.append(fact) }
        case .questStateChanged:
            if let questID = event.targetID, var quest = quests[questID] {
                if let statusRaw = event.text, let status = QuestStatus(rawValue: statusRaw) { quest.status = status }
                quests[questID] = quest
            }
        case .timeAdvanced:
            minutesElapsed += event.value ?? 0
        }
        eventLog.append(event)
    }
}
