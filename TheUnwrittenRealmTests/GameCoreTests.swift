import XCTest
@testable import TheUnwrittenRealm

final class GameCoreTests: XCTestCase {
    func testSkillCheckUsesInjectedRoll() {
        var state = StarterCampaign.make()
        var engine = RulesEngine()
        let action = InterpretedAction(intent: .investigate, approach: "inspect the map", desiredOutcome: "learn something")
        var random: any RandomSource = SequenceRandomSource([20])
        let result = engine.resolve(action, in: state, random: &random)
        XCTAssertEqual(result.check?.roll, 20)
        XCTAssertEqual(result.check?.outcome, .criticalSuccess)
        XCTAssertTrue(result.events.contains(where: { $0.kind == GameEventKind.skillCheckResolved }))
    }

    func testMissingItemCannotMutateInventory() {
        let state = StarterCampaign.make()
        var engine = RulesEngine()
        let action = InterpretedAction(intent: .useItem, approach: "drink it", desiredOutcome: "become invisible", referencedItemName: "invisibility potion")
        var random: any RandomSource = SequenceRandomSource([1])
        let result = engine.resolve(action, in: state, random: &random)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.events.isEmpty)
    }

    func testTravelAppliesOnlyToConnectedLocation() {
        var state = StarterCampaign.make()
        var engine = RulesEngine()
        let action = InterpretedAction(intent: .travel, approach: "go to the chapel", desiredOutcome: "arrive", destinationID: "chapel")
        var random: any RandomSource = SequenceRandomSource([10])
        let result = engine.resolve(action, in: state, random: &random)
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(state.currentLocationID, "tavern")
    }

    func testApplyEventsMutatesCanonicalState() {
        var state = StarterCampaign.make()
        state.apply(GameEvent(kind: .locationChanged, targetID: "square", text: "Village Square"))
        state.apply(GameEvent(kind: .npcDispositionChanged, targetID: "elian", value: 12))
        state.apply(GameEvent(kind: .factDiscovered, text: "A hidden bell marks the safe path."))
        XCTAssertEqual(state.currentLocationID, "square")
        XCTAssertEqual(state.npcs["elian"]?.disposition, 12)
        XCTAssertTrue(state.discoveredFacts.contains("A hidden bell marks the safe path."))
    }

    func testContextDoesNotLeakNPCSecrets() {
        let state = StarterCampaign.make()
        let context = ContextBuilder().build(for: state)
        let mira = try! XCTUnwrap(context.nearbyNPCs.first(where: { $0.id == "mira" }))
        XCTAssertTrue(mira.knownFacts.contains("The duke's seal opens the vault."))
        XCTAssertFalse(mira.knownFacts.contains("She once worked for the duke's spies."))
    }

    func testSaveRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = JSONCampaignStore(url: directory.appendingPathComponent("campaign.json"))
        let original = StarterCampaign.make()
        try store.save(original)
        XCTAssertEqual(try store.load(), original)
        try store.delete()
    }

    func testNarrationFailurePreservesResolvedEvents() async {
        struct FailingNarrator: AIProvider {
            func interpret(command: PlayerCommand, context: DMContext) async throws -> InterpretedAction { InterpretedAction(intent: .investigate, approach: command.rawText, desiredOutcome: "learn") }
            func narrate(context: NarrationContext) async throws -> String { throw AIProviderError.unavailable }
            func extractMemories(context: NarrationContext) async throws -> [MemoryCandidate] { [] }
        }
        var state = StarterCampaign.make()
        var engine = GameTurnEngine(ai: FailingNarrator(), random: SequenceRandomSource([20]))
        let result = await engine.process(PlayerCommand(rawText: "inspect the altar"), state: &state) { _ in }
        XCTAssertFalse(result.events.isEmpty)
        XCTAssertEqual(state.turnNumber, 1)
        XCTAssertTrue(state.recentTurns.last?.text.contains("world") == true)
    }
}
