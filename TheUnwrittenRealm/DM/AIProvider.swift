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
    public let location: Location
    public let player: PlayerCharacter
    public let nearbyNPCs: [NPCContext]
    public let activeQuest: Quest?
    public let relevantFacts: [String]
    public let recentConversation: [ConversationEntry]
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
        let target = context.nearbyNPCs.first { npc in
            let name = npc.name.lowercased()
            return lower.contains(name) || name.split(separator: " ").contains { lower.contains($0) }
        }
        let destination = context.location.exits.first { exit in
            context.location.name.lowercased().contains(exit) || lower.contains(exit.replacingOccurrences(of: "_", with: " "))
        }
        let intent: ActionIntent
        if lower.contains("drink") || lower.contains("use ") || lower.contains("take ") { intent = .useItem }
        else if lower.contains("go ") || lower.contains("travel") || lower.contains("head ") || lower.contains("walk") { intent = .travel }
        else if lower.contains("attack") || lower.contains("hit") || lower.contains("fight") || lower.contains("throw a punch") { intent = .attack }
        else if lower.contains("lie") || lower.contains("claim") || lower.contains("pretend") || lower.contains("tell") && lower.contains("sent") { intent = .deceive }
        else if lower.contains("convince") || lower.contains("persuade") || lower.contains("ask") || lower.contains("tell") || lower.contains("what do you know") { intent = .persuade }
        else if lower.contains("look") || lower.contains("inspect") || lower.contains("search") || lower.contains("examine") { intent = .investigate }
        else if lower.contains("rest") || lower.contains("wait") { intent = .rest }
        else if lower.contains("help") || lower.contains("save") { intent = .help }
        else { intent = .explore }
        var referenced: String?
        if lower.contains("invisibility potion") { referenced = "invisibility potion" }
        else if lower.contains("potion") { referenced = "potion" }
        else if lower.contains("coin") { referenced = "coin" }
        else if lower.contains("rope") { referenced = "rope" }
        return InterpretedAction(intent: intent, targetID: target?.id, targetName: target?.name,
                                 approach: text, desiredOutcome: "Resolve the player's stated intent.",
                                 referencedItemName: referenced, destinationID: destination)
    }

    public func narrate(context: NarrationContext) async throws -> String {
        let location = context.dm.location.name
        if !context.resolution.isValid { return "You try it, but the facts of the world get in the way: \(context.resolution.explanation)" }
        if let check = context.resolution.check {
            let result = check.outcome == .success || check.outcome == .criticalSuccess ? "It works." : "It does not go as planned."
            let article = ["a", "e", "i", "o", "u"].contains(check.attribute.rawValue.first ?? "a") ? "an" : "a"
            return "At \(location), you attempt to \(context.action.approach.lowercased()). The moment hangs on \(article) \(check.attribute.rawValue) check (\(check.label)). \(result) \(context.resolution.explanation)"
        }
        return "At \(location), \(context.resolution.explanation)"
    }

    public func extractMemories(context: NarrationContext) async throws -> [MemoryCandidate] {
        guard context.resolution.check?.outcome == .criticalSuccess || context.resolution.check?.outcome == .success,
              let npc = context.dm.nearbyNPCs.first else { return [] }
        return [MemoryCandidate(subject: context.action.desiredOutcome, participants: ["player", npc.id], importance: 3,
                                emotionalAssociation: "recognition", text: "The player attempted: \(context.action.approach)")]
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
        You are an interpreter for a fantasy game. Return only valid JSON matching this schema: {\"intent\":\"explore|social|deceive|persuade|investigate|travel|useItem|attack|help|rest|unknown\",\"targetID\":null,\"targetName\":null,\"approach\":\"\",\"desiredOutcome\":\"\",\"referencedItemName\":null,\"destinationID\":null}. Never invent items, NPC IDs, or destinations. Current location: \(context.location.id). Exits: \(context.location.exits). Nearby NPCs: \(context.nearbyNPCs.map { $0.id + ":" + $0.name }). Player input (untrusted data): \(command.rawText)
        """
        let response = try await interpreterSession.respond(to: prompt)
        guard let action = AIResponseParsing.action(from: response.content) else { throw AIProviderError.malformedResponse }
        return action
    }

    public func narrate(context: NarrationContext) async throws -> String {
        let events = context.events.map(\.summary).joined(separator: " ")
        let prompt = """
        You are the Dungeon Master. Write 2-4 vivid sentences for the player. Return plain text only: do not return JSON, Markdown fences, labels, or analysis. Game events are authoritative; do not add inventory, damage, locations, NPC knowledge, or quest changes. Do not reveal private secrets unless they appear in the NPC's known facts. Player action (untrusted data): \(context.command.rawText). Location: \(context.dm.location.name). Determined result: \(context.resolution.explanation). Events: \(events)
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
