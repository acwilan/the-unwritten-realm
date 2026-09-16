import Foundation
import SwiftUI

@MainActor
public final class GameSession: ObservableObject {
    @Published public private(set) var campaign: CampaignState?
    @Published public private(set) var isProcessing = false
    @Published public var errorMessage: String?
    @Published public private(set) var lastCheck: SkillCheck?
    @Published public private(set) var lastDiagnostics: TurnDiagnostics?
    @Published public private(set) var foundationModelAvailability: FoundationModelAvailability

    private let store: any CampaignStore
    private let ai: any AIProvider
    private var turnEngine: GameTurnEngine

    public init(store: any CampaignStore = JSONCampaignStore(), ai: any AIProvider = GameSession.defaultAI()) {
        self.store = store
        self.ai = ai
        self.turnEngine = GameTurnEngine(ai: ai)
        self.foundationModelAvailability = FoundationModelStatus.current
        self.campaign = try? store.load()
    }

    public nonisolated static func defaultAI() -> any AIProvider {
        #if targetEnvironment(simulator)
        // The Simulator does not reliably provide the device's on-device model runtime.
        return FakeAIProvider()
        #else
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return FallbackAIProvider(primary: FoundationModelsAIProvider(), fallback: FakeAIProvider())
        }
        #endif
        return FakeAIProvider()
        #endif
    }

    public func startNewCampaign(profile: CharacterCreationProfile = .default, language: AppLanguage = .english) {
        campaign = StarterCampaign.make(profile: profile)
        do { try store.save(campaign!) } catch {
            errorMessage = AppLocalization.string("Could not save the new campaign.", language: language)
        }
    }

    public func continueCampaign(language: AppLanguage = .english) {
        do { campaign = try store.load() } catch {
            errorMessage = AppLocalization.string("Could not load the campaign.", language: language)
        }
    }

    public func deleteCampaign(language: AppLanguage = .english) {
        do { try store.delete(); campaign = nil } catch {
            errorMessage = AppLocalization.string("Could not delete the campaign.", language: language)
        }
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
