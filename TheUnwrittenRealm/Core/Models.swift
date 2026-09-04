import Foundation

public struct PlayerCommand: Codable, Equatable, Sendable {
    public let id: UUID
    public let rawText: String

    public init(id: UUID = UUID(), rawText: String) {
        self.id = id
        self.rawText = rawText
    }
}

public enum Attribute: String, Codable, CaseIterable, Sendable {
    case might
    case finesse
    case insight
    case presence
}

public enum ActionIntent: String, Codable, Sendable {
    case explore
    case social
    case deceive
    case persuade
    case investigate
    case travel
    case useItem
    case attack
    case help
    case rest
    case unknown
}

public struct InterpretedAction: Codable, Equatable, Sendable {
    public var intent: ActionIntent
    public var targetID: String?
    public var targetName: String?
    public var approach: String
    public var desiredOutcome: String
    public var referencedItemName: String?
    public var destinationID: String?

    public init(intent: ActionIntent, targetID: String? = nil, targetName: String? = nil,
                approach: String, desiredOutcome: String, referencedItemName: String? = nil,
                destinationID: String? = nil) {
        self.intent = intent
        self.targetID = targetID
        self.targetName = targetName
        self.approach = approach
        self.desiredOutcome = desiredOutcome
        self.referencedItemName = referencedItemName
        self.destinationID = destinationID
    }
}

public struct Item: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let usable: Bool

    public init(id: String, name: String, description: String, usable: Bool = false) {
        self.id = id
        self.name = name
        self.description = description
        self.usable = usable
    }
}

public struct PlayerCharacter: Codable, Equatable, Sendable {
    public var name: String
    public var level: Int
    public var hitPoints: Int
    public var maxHitPoints: Int
    public var attributes: [Attribute: Int]
    public var inventory: [Item]

    public func modifier(for attribute: Attribute) -> Int {
        (attributes[attribute, default: 0] - 10) / 2
    }
}

public struct Memory: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let subject: String
    public let participants: [String]
    public let importance: Int
    public let emotionalAssociation: String
    public let text: String

    public init(id: UUID = UUID(), subject: String, participants: [String], importance: Int,
                emotionalAssociation: String, text: String) {
        self.id = id
        self.subject = subject
        self.participants = participants
        self.importance = importance
        self.emotionalAssociation = emotionalAssociation
        self.text = text
    }
}

public struct NPC: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let role: String
    public let personality: [String]
    public let goal: String
    public var disposition: Int
    public var knownFacts: [String]
    public var secrets: [String]
    public var memories: [Memory]
    public var emotionalState: String
    public let locationID: String

    public init(id: String, name: String, role: String, personality: [String], goal: String,
                disposition: Int, knownFacts: [String], secrets: [String], memories: [Memory] = [],
                emotionalState: String, locationID: String) {
        self.id = id
        self.name = name
        self.role = role
        self.personality = personality
        self.goal = goal
        self.disposition = disposition
        self.knownFacts = knownFacts
        self.secrets = secrets
        self.memories = memories
        self.emotionalState = emotionalState
        self.locationID = locationID
    }
}

public struct Location: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let exits: [String]
    public let npcIDs: [String]

    public init(id: String, name: String, description: String, exits: [String], npcIDs: [String]) {
        self.id = id
        self.name = name
        self.description = description
        self.exits = exits
        self.npcIDs = npcIDs
    }
}

public enum QuestStatus: String, Codable, Sendable {
    case notStarted
    case active
    case completed
}

public struct Quest: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public var status: QuestStatus
    public var objective: String
}

public struct ConversationEntry: Codable, Identifiable, Equatable, Sendable {
    public enum Speaker: String, Codable, Sendable { case player, narrator, npc }
    public let id: UUID
    public let speaker: Speaker
    public let speakerName: String?
    public let text: String
    public let eventSummaries: [String]
    public let date: Date

    public init(id: UUID = UUID(), speaker: Speaker, speakerName: String? = nil, text: String,
                eventSummaries: [String] = [], date: Date = Date()) {
        self.id = id
        self.speaker = speaker
        self.speakerName = speakerName
        self.text = text
        self.eventSummaries = eventSummaries
        self.date = date
    }
}

public struct CampaignState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    public var campaignID: UUID
    public var title: String
    public var player: PlayerCharacter
    public var currentLocationID: String
    public var locations: [String: Location]
    public var npcs: [String: NPC]
    public var quests: [String: Quest]
    public var discoveredFacts: [String]
    public var recentTurns: [ConversationEntry]
    public var eventLog: [GameEvent]
    public var turnNumber: Int
    public var minutesElapsed: Int

    public init(schemaVersion: Int = CampaignState.currentSchemaVersion, campaignID: UUID = UUID(), title: String,
                player: PlayerCharacter, currentLocationID: String, locations: [String: Location],
                npcs: [String: NPC], quests: [String: Quest], discoveredFacts: [String] = [],
                recentTurns: [ConversationEntry] = [], eventLog: [GameEvent] = [], turnNumber: Int = 0,
                minutesElapsed: Int = 0) {
        self.schemaVersion = schemaVersion
        self.campaignID = campaignID
        self.title = title
        self.player = player
        self.currentLocationID = currentLocationID
        self.locations = locations
        self.npcs = npcs
        self.quests = quests
        self.discoveredFacts = discoveredFacts
        self.recentTurns = recentTurns
        self.eventLog = eventLog
        self.turnNumber = turnNumber
        self.minutesElapsed = minutesElapsed
    }

    public var currentLocation: Location? { locations[currentLocationID] }
    public var activeQuest: Quest? { quests.values.first(where: { $0.status == .active }) }
}
