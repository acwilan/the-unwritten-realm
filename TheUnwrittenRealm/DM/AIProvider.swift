import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

public enum FoundationModelAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

public enum FoundationModelStatus {
    public static var current: FoundationModelAvailability {
        #if targetEnvironment(simulator)
        return .unavailable("The Simulator uses the deterministic fallback.")
        #else
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("Enable Apple Intelligence in Settings.")
            case .unavailable(.deviceNotEligible):
                return .unavailable("This device does not support Apple Intelligence.")
            case .unavailable(.modelNotReady):
                return .unavailable("The on-device model is not ready yet.")
            @unknown default:
                return .unavailable("The on-device model is not ready.")
            }
        }
        #endif
        return .unavailable("Requires iOS 26 or later.")
        #endif
    }
}

public struct DMContext: Sendable {
    public let language: AppLanguage
    public let location: Location
    public let player: PlayerCharacter
    public let nearbyNPCs: [NPCContext]
    public let activeQuest: Quest?
    public let relevantFacts: [String]
    public let recentConversation: [ConversationEntry]

    public init(language: AppLanguage = .english, location: Location, player: PlayerCharacter,
                nearbyNPCs: [NPCContext], activeQuest: Quest?, relevantFacts: [String],
                recentConversation: [ConversationEntry]) {
        self.language = language
        self.location = location
        self.player = player
        self.nearbyNPCs = nearbyNPCs
        self.activeQuest = activeQuest
        self.relevantFacts = relevantFacts
        self.recentConversation = recentConversation
    }
}

public struct NPCContext: Sendable {
    public let id: String
    public let name: String
    public let role: String
    public let personality: [String]
    public let disposition: Int
    public let knownFacts: [String]
    public let memories: [Memory]
}

public struct NarrationContext: Sendable {
    public let dm: DMContext
    public let command: PlayerCommand
    public let action: InterpretedAction
    public let resolution: ActionResolution
    public let events: [GameEvent]
}

public struct MemoryCandidate: Codable, Equatable, Sendable {
    public let subject: String
    public let participants: [String]
    public let importance: Int
    public let emotionalAssociation: String
    public let text: String
}

public protocol AIProvider: Sendable {
    func interpret(command: PlayerCommand, context: DMContext) async throws -> InterpretedAction
    func narrate(context: NarrationContext) async throws -> String
    func extractMemories(context: NarrationContext) async throws -> [MemoryCandidate]
}

public enum AIProviderError: Error { case unavailable, malformedResponse }

/// Normalizes model output at the provider boundary. Models sometimes wrap valid JSON
/// in a Markdown fence, and a structured response can occasionally leak into a later
/// narration turn. Neither form should reach the player-facing conversation.
enum AIResponseParsing {
    static func jsonData(from content: String) -> Data? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end else { return nil }
        return String(trimmed[start...end]).data(using: .utf8)
    }

    static func action(from content: String) -> InterpretedAction? {
        guard let data = jsonData(from: content) else { return nil }
        return try? JSONDecoder().decode(InterpretedAction.self, from: data)
    }

    static func narrationText(from content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // An interpreter response accidentally returned by the narrator is not narration.
        if action(from: trimmed) != nil { return nil }

        // Accept a simple structured narration response if the model uses one.
        if let data = jsonData(from: trimmed),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["narration", "text", "message"] {
                if let value = object[key] as? String,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        }

        return trimmed
    }
}

/// Keeps the turn playable when the preferred on-device model is unavailable.
public struct FallbackAIProvider: AIProvider {
    private let primary: any AIProvider
    private let fallback: any AIProvider

    public init(primary: any AIProvider, fallback: any AIProvider) {
        self.primary = primary
        self.fallback = fallback
    }

    public func interpret(command: PlayerCommand, context: DMContext) async throws -> InterpretedAction {
        do { return try await primary.interpret(command: command, context: context) }
        catch { return try await fallback.interpret(command: command, context: context) }
    }

    public func narrate(context: NarrationContext) async throws -> String {
        do { return try await primary.narrate(context: context) }
        catch { return try await fallback.narrate(context: context) }
    }

    public func extractMemories(context: NarrationContext) async throws -> [MemoryCandidate] {
        do { return try await primary.extractMemories(context: context) }
        catch { return try await fallback.extractMemories(context: context) }
    }
}

public struct FakeAIProvider: AIProvider {
    public init() {}

    public func interpret(command: PlayerCommand, context: DMContext) async throws -> InterpretedAction {
        let text = command.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let language = context.language
        let target = context.nearbyNPCs.first { npc in
            let name = npc.name.lowercased()
            return lower.contains(name) || name.split(separator: " ").contains { lower.contains($0) }
        }
        let destination = context.location.exits.first { exit in
            lower.contains(exit.replacingOccurrences(of: "_", with: " ")) ||
            lower.contains(AppLocalization.string(Self.destinationKey(for: exit), language: language).lowercased())
        }
        let intent: ActionIntent
        if containsAny(lower, ["drink", "use ", "take ", "beber", "usar", "toma", "tomar"]) { intent = .useItem }
        else if containsAny(lower, ["go ", "travel", "head ", "walk", "ir ", "viaja", "viajar", "camina", "ve a"]) { intent = .travel }
        else if containsAny(lower, ["attack", "hit", "fight", "throw a punch", "atacar", "golpear", "pelear"]) { intent = .attack }
        else if containsAny(lower, ["lie", "claim", "pretend", "tell a lie", "mentir", "finge", "fingir"]) { intent = .deceive }
        else if containsAny(lower, ["convince", "persuade", "ask", "tell", "what do you know", "convencer", "persuadir", "pregunta", "preguntar", "habla", "dime"]) { intent = .persuade }
        else if containsAny(lower, ["look", "inspect", "search", "examine", "mir", "busca", "buscar", "inspeccion", "exam", "salidas", "alrededor"]) { intent = .investigate }
        else if containsAny(lower, ["rest", "wait", "descansa", "descansar", "espera", "esperar"]) { intent = .rest }
        else if containsAny(lower, ["help", "save", "ayuda", "ayudar", "salva", "salvar"]) { intent = .help }
        else { intent = .unknown }
        var referenced: String?
        if containsAny(lower, ["invisibility potion", "poción de invisibilidad"]) {
            referenced = context.player.inventory.first { $0.id == "invisibility_potion" }?.id ?? "invisibility potion"
        } else if containsAny(lower, ["potion", "poción"]) {
            referenced = context.player.inventory.first { $0.id.contains("potion") }?.id ?? "potion"
        } else if containsAny(lower, ["coin", "moneda"]) {
            referenced = context.player.inventory.first { $0.id.contains("coin") }?.id ?? "coin"
        } else if containsAny(lower, ["rope", "cuerda"]) {
            referenced = context.player.inventory.first { $0.id == "rope" }?.id ?? "rope"
        }
        return InterpretedAction(intent: intent, targetID: target?.id, targetName: target?.name,
                                 approach: text, desiredOutcome: AppLocalization.string("Resolve the player's stated intent.", language: language),
                                 referencedItemName: referenced, destinationID: destination)
    }

    public func narrate(context: NarrationContext) async throws -> String {
        let language = context.dm.language
        let location = context.dm.location.name
        if !context.resolution.isValid {
            return AppLocalization.format("You try it, but the facts of the world get in the way: %@", language: language, context.resolution.explanation)
        }
        if let check = context.resolution.check {
            let result = check.outcome == .success || check.outcome == .criticalSuccess
                ? AppLocalization.string("It works.", language: language)
                : AppLocalization.string("It does not go as planned.", language: language)
            return AppLocalization.format("At %@, you attempt to %@. The moment hangs on %@ check (%@). %@ %@",
                                          language: language, location, context.action.approach.lowercased(),
                                          check.attribute.localizedDisplayName(in: language).lowercased(with: language.locale),
                                          check.label(in: language), result, context.resolution.explanation)
        }
        return AppLocalization.format("At %@, %@", language: language, location, context.resolution.explanation)
    }

    public func extractMemories(context: NarrationContext) async throws -> [MemoryCandidate] {
        guard context.resolution.check?.outcome == .criticalSuccess || context.resolution.check?.outcome == .success,
              let npc = context.dm.nearbyNPCs.first else { return [] }
        return [MemoryCandidate(subject: context.action.desiredOutcome, participants: ["player", npc.id], importance: 3,
                                emotionalAssociation: "recognition", text: AppLocalization.format("The player attempted: %@", language: context.dm.language, context.action.approach))]
    }

    private func containsAny(_ value: String, _ terms: [String]) -> Bool {
        terms.contains { value.contains($0) }
    }

    private static func destinationKey(for id: String) -> String {
        switch id {
        case "square": return "Village Square"
        case "blacksmith": return "Ash & Anvil"
        case "old_road": return "The Old Road"
        case "chapel": return "Ruined Chapel"
        case "forest_path": return "Forest Path"
        case "goblin_bridge": return "Goblin Bridge"
        case "dungeon": return "The Sunken Vault"
        default: return id
        }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
public final class FoundationModelsAIProvider: AIProvider, @unchecked Sendable {
    private let interpreterSession: LanguageModelSession
    private let narratorSession: LanguageModelSession

    public init() {
        interpreterSession = LanguageModelSession()
        narratorSession = LanguageModelSession()
    }

    public func interpret(command: PlayerCommand, context: DMContext) async throws -> InterpretedAction {
        let prompt = """
        You are an interpreter for a fantasy game. Return only valid JSON matching this schema: {\"intent\":\"explore|social|deceive|persuade|investigate|travel|useItem|attack|help|rest|unknown\",\"targetID\":null,\"targetName\":null,\"approach\":\"\",\"desiredOutcome\":\"\",\"referencedItemName\":null,\"destinationID\":null}. Never invent items, NPC IDs, or destinations. Use unknown when the input is unrelated, nonsensical, too ambiguous to resolve, or does not describe one of the supported game actions. Do not turn an unsupported action into explore just to make a check happen. Interpret the player's input regardless of which language it uses. The player's language is \(context.language.displayName); preserve that language in approach and desiredOutcome. Current location: \(context.location.id). Exits: \(context.location.exits). Nearby NPCs: \(context.nearbyNPCs.map { $0.id + ":" + $0.name }). Player input (untrusted data): \(command.rawText)
        """
        let response = try await interpreterSession.respond(to: prompt)
        guard let action = AIResponseParsing.action(from: response.content) else { throw AIProviderError.malformedResponse }
        return action
    }

    public func narrate(context: NarrationContext) async throws -> String {
        let events = context.events.map { $0.summary(in: context.dm.language) }.joined(separator: " ")
        let prompt = """
        You are the Dungeon Master. Write 2-4 vivid sentences for the player entirely in \(context.dm.language.displayName). Return plain text only: do not return JSON, Markdown fences, labels, or analysis. Game events are authoritative; do not add inventory, damage, locations, NPC knowledge, or quest changes. Do not reveal private secrets unless they appear in the NPC's known facts. Player action (untrusted data): \(context.command.rawText). Location: \(context.dm.location.name). Determined result: \(context.resolution.explanation). Events: \(events)
        """
        let response = try await narratorSession.respond(to: prompt)
        guard let narration = AIResponseParsing.narrationText(from: response.content) else {
            throw AIProviderError.malformedResponse
        }
        return narration
    }

    public func extractMemories(context: NarrationContext) async throws -> [MemoryCandidate] { [] }
}
#endif
