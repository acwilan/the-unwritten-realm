import Foundation

public enum CampaignDifficulty: String, Codable, CaseIterable, Identifiable, Sendable {
    case easy
    case difficult

    public var id: String { rawValue }

    public var targetAdjustment: Int {
        switch self {
        case .easy: return -2
        case .difficult: return 2
        }
    }

    public func adjustedTarget(_ baseTarget: Int) -> Int {
        baseTarget + targetAdjustment
    }
}

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

public enum CharacterType: String, Codable, CaseIterable, Identifiable, Sendable {
    case vanguard
    case shadow
    case lorekeeper
    case envoy

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vanguard: return "Vanguard"
        case .shadow: return "Shadow"
        case .lorekeeper: return "Lorekeeper"
        case .envoy: return "Envoy"
        }
    }

    public var icon: String {
        switch self {
        case .vanguard: return "shield.lefthalf.filled"
        case .shadow: return "eye.slash.fill"
        case .lorekeeper: return "book.closed.fill"
        case .envoy: return "bubble.left.and.bubble.right.fill"
        }
    }

    public var summary: String {
        switch self {
        case .vanguard: return "A steadfast frontliner who meets danger head-on."
        case .shadow: return "A nimble observer who finds the quiet way through."
        case .lorekeeper: return "A seeker of hidden patterns, old magic, and buried truth."
        case .envoy: return "A perceptive negotiator who turns strangers into allies."
        }
    }

    public var startingAttributes: [Attribute: Int] {
        switch self {
        case .vanguard: return [.might: 15, .finesse: 10, .insight: 10, .presence: 10]
        case .shadow: return [.might: 10, .finesse: 15, .insight: 12, .presence: 8]
        case .lorekeeper: return [.might: 8, .finesse: 10, .insight: 15, .presence: 12]
        case .envoy: return [.might: 9, .finesse: 10, .insight: 12, .presence: 15]
        }
    }

    public var startingHitPoints: Int {
        self == .vanguard ? 12 : 10
    }
}

public struct CharacterAbility: Identifiable, Equatable, Sendable {
    public let name: String
    public let description: String

    public var id: String { name }

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }
}

public struct CharacterCreationProfile: Equatable, Sendable {
    public var name: String
    public var type: CharacterType
    public var abilities: [String]

    public init(name: String, type: CharacterType, abilities: [String]) {
        self.name = name
        self.type = type
        self.abilities = abilities
    }

    public static let `default` = CharacterCreationProfile(
        name: "Wayfarer",
        type: .lorekeeper,
        abilities: ["Read the Unseen", "Keen Eye"]
    )

    public static let availableAbilities: [CharacterAbility] = [
        CharacterAbility(name: "Keen Eye", description: "Notice small details, tracks, and hidden mechanisms."),
        CharacterAbility(name: "Quiet Step", description: "Move with care when the world is listening."),
        CharacterAbility(name: "Read the Unseen", description: "Recognize old symbols, magic, and unsettling patterns."),
        CharacterAbility(name: "Silver Tongue", description: "Find the words that open guarded conversations."),
        CharacterAbility(name: "Hold the Line", description: "Stand firm when fear or force tries to move you."),
        CharacterAbility(name: "Field Medic", description: "Keep a companion or yourself moving after a hard encounter.")
    ]
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
    public var characterType: CharacterType
    public var abilities: [String]
    public var level: Int
    public var hitPoints: Int
    public var maxHitPoints: Int
    public var attributes: [Attribute: Int]
    public var inventory: [Item]

    public init(name: String, level: Int, hitPoints: Int, maxHitPoints: Int,
                attributes: [Attribute: Int], inventory: [Item],
                characterType: CharacterType = .vanguard, abilities: [String] = []) {
        self.name = name
        self.characterType = characterType
        self.abilities = abilities
        self.level = level
        self.hitPoints = hitPoints
        self.maxHitPoints = maxHitPoints
        self.attributes = attributes
        self.inventory = inventory
    }

    private enum CodingKeys: String, CodingKey {
        case name, characterType, abilities, level, hitPoints, maxHitPoints, attributes, inventory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        characterType = try container.decodeIfPresent(CharacterType.self, forKey: .characterType) ?? .vanguard
        abilities = try container.decodeIfPresent([String].self, forKey: .abilities) ?? []
        level = try container.decode(Int.self, forKey: .level)
        hitPoints = try container.decode(Int.self, forKey: .hitPoints)
        maxHitPoints = try container.decode(Int.self, forKey: .maxHitPoints)
        attributes = try container.decode([Attribute: Int].self, forKey: .attributes)
        inventory = try container.decode([Item].self, forKey: .inventory)
    }

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
    public static let currentSchemaVersion = 2
    public var schemaVersion: Int
    public var campaignID: UUID
    public var title: String
    public var difficulty: CampaignDifficulty
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
                difficulty: CampaignDifficulty = .easy,
                player: PlayerCharacter, currentLocationID: String, locations: [String: Location],
                npcs: [String: NPC], quests: [String: Quest], discoveredFacts: [String] = [],
                recentTurns: [ConversationEntry] = [], eventLog: [GameEvent] = [], turnNumber: Int = 0,
                minutesElapsed: Int = 0) {
        self.schemaVersion = schemaVersion
        self.campaignID = campaignID
        self.title = title
        self.difficulty = difficulty
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

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, campaignID, title, difficulty, player, currentLocationID, locations, npcs, quests
        case discoveredFacts, recentTurns, eventLog, turnNumber, minutesElapsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = max(try container.decode(Int.self, forKey: .schemaVersion), CampaignState.currentSchemaVersion)
        campaignID = try container.decode(UUID.self, forKey: .campaignID)
        title = try container.decode(String.self, forKey: .title)
        difficulty = try container.decodeIfPresent(CampaignDifficulty.self, forKey: .difficulty) ?? .easy
        player = try container.decode(PlayerCharacter.self, forKey: .player)
        currentLocationID = try container.decode(String.self, forKey: .currentLocationID)
        locations = try container.decode([String: Location].self, forKey: .locations)
        npcs = try container.decode([String: NPC].self, forKey: .npcs)
        quests = try container.decode([String: Quest].self, forKey: .quests)
        discoveredFacts = try container.decode([String].self, forKey: .discoveredFacts)
        recentTurns = try container.decode([ConversationEntry].self, forKey: .recentTurns)
        eventLog = try container.decode([GameEvent].self, forKey: .eventLog)
        turnNumber = try container.decode(Int.self, forKey: .turnNumber)
        minutesElapsed = try container.decode(Int.self, forKey: .minutesElapsed)
    }

    public var currentLocation: Location? { locations[currentLocationID] }
    public var activeQuest: Quest? { quests.values.first(where: { $0.status == .active }) }
}
