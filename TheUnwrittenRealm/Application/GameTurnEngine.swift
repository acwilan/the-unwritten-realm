import Foundation

public struct TurnDiagnostics: Sendable {
    public let rawCommand: String
    public let action: InterpretedAction
    public let check: SkillCheck?
    public let events: [GameEvent]
    public let locationID: String
    public let contextNPCIDs: [String]
}

public struct GameTurnResult: Sendable {
    public let narration: String
    public let events: [GameEvent]
    public let action: InterpretedAction?
    public let check: SkillCheck?
    public let errorMessage: String?
    public let diagnostics: TurnDiagnostics?
}

public struct GameTurnEngine: Sendable {
    private let contextBuilder: ContextBuilder
    private let ai: any AIProvider
    private var random: any RandomSource
    private var rules = RulesEngine()

    public init(ai: any AIProvider, random: any RandomSource = SystemRandomSource()) {
        self.ai = ai
        self.random = random
        self.contextBuilder = ContextBuilder()
    }

    public typealias SaveHandler = @Sendable (CampaignState) throws -> Void

    public mutating func process(_ command: PlayerCommand, state: inout CampaignState, save: SaveHandler) async -> GameTurnResult {
        let context = contextBuilder.build(for: state)
        let action: InterpretedAction
        do {
            action = try await ai.interpret(command: command, context: context)
        } catch {
            return GameTurnResult(narration: "I couldn't understand that attempt. Try describing what you want to do in a little more detail.", events: [], action: nil, check: nil, errorMessage: "Intent interpretation failed: \(error.localizedDescription)", diagnostics: nil)
        }
        let resolution = rules.resolve(action, in: state, random: &random)
        for event in resolution.events { state.apply(event) }
        state.turnNumber += 1
        state.recentTurns.append(ConversationEntry(speaker: .player, text: command.rawText))

        let postContext = contextBuilder.build(for: state)
        let narrationContext = NarrationContext(dm: postContext, command: command, action: action, resolution: resolution, events: resolution.events)
        let narration: String
        do {
            narration = try await ai.narrate(context: narrationContext)
        } catch {
            narration = resolution.isValid ? "The world shifts around your choice. \(resolution.explanation)" : resolution.explanation
        }
        state.recentTurns.append(ConversationEntry(speaker: .narrator, text: narration, eventSummaries: resolution.events.map(\.summary)))

        if let targetID = resolution.targetNPCID, var npc = state.npcs[targetID], let candidates = try? await ai.extractMemories(context: narrationContext) {
            for candidate in candidates where candidate.importance >= 3 {
                let memory = Memory(subject: candidate.subject, participants: candidate.participants, importance: candidate.importance, emotionalAssociation: candidate.emotionalAssociation, text: candidate.text)
                if !npc.memories.contains(where: { $0.text == memory.text }) { npc.memories.append(memory) }
            }
            state.npcs[targetID] = npc
        }
        state.recentTurns = Array(state.recentTurns.suffix(40))
        do {
            try save(state)
        } catch {
            return GameTurnResult(narration: narration, events: resolution.events, action: action, check: resolution.check, errorMessage: "The turn played, but the campaign could not be saved.", diagnostics: nil)
        }
        let diagnostics = TurnDiagnostics(rawCommand: command.rawText, action: action, check: resolution.check,
                                          events: resolution.events, locationID: context.location.id,
                                          contextNPCIDs: context.nearbyNPCs.map(\.id))
        return GameTurnResult(narration: narration, events: resolution.events, action: action, check: resolution.check, errorMessage: nil, diagnostics: diagnostics)
    }
}
