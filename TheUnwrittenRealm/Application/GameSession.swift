import Foundation
import SwiftUI

@MainActor
public final class GameSession: ObservableObject {
    @Published public private(set) var campaign: CampaignState?
    @Published public private(set) var isProcessing = false
    @Published public var errorMessage: String?
    @Published public private(set) var lastCheck: SkillCheck?
    @Published public private(set) var lastDiagnostics: TurnDiagnostics?

    private let store: any CampaignStore
    private let ai: any AIProvider
    private var turnEngine: GameTurnEngine

    public init(store: any CampaignStore = JSONCampaignStore(), ai: any AIProvider = GameSession.defaultAI()) {
        self.store = store
        self.ai = ai
        self.turnEngine = GameTurnEngine(ai: ai)
        self.campaign = try? store.load()
    }

    public nonisolated static func defaultAI() -> any AIProvider {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return FoundationModelsAIProvider() }
        #endif
        return FakeAIProvider()
    }

    public func startNewCampaign() {
        campaign = StarterCampaign.make()
        do { try store.save(campaign!) } catch { errorMessage = "Could not save the new campaign." }
    }

    public func continueCampaign() {
        do { campaign = try store.load() } catch { errorMessage = "Could not load the campaign." }
    }

    public func deleteCampaign() {
        do { try store.delete(); campaign = nil } catch { errorMessage = "Could not delete the campaign." }
    }

    public func submit(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isProcessing, var current = campaign else { return }
        isProcessing = true
        errorMessage = nil
        Task { @MainActor in
            var engine = turnEngine
            let result = await engine.process(PlayerCommand(rawText: text), state: &current) { updated in
                try store.save(updated)
            }
            turnEngine = engine
            campaign = current
            lastCheck = result.check
            lastDiagnostics = result.diagnostics
            errorMessage = result.errorMessage
            isProcessing = false
        }
    }
}
