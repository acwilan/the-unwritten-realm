import XCTest
@testable import TheUnwrittenRealm

final class GameCoreTests: XCTestCase {
    func testStarterCampaignUsesCustomCharacterProfile() {
        let profile = CharacterCreationProfile(name: "Juniper", type: .shadow, abilities: ["Quiet Step", "Keen Eye"])
        let campaign = StarterCampaign.make(profile: profile)

        XCTAssertEqual(campaign.player.name, "Juniper")
        XCTAssertEqual(campaign.player.characterType, .shadow)
        XCTAssertEqual(campaign.player.abilities, ["Quiet Step", "Keen Eye"])
        XCTAssertEqual(campaign.player.attributes[.finesse], 15)
        XCTAssertEqual(campaign.player.maxHitPoints, 10)
    }

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

    func testSuccessfulInvestigationDiscoversLocationClue() {
        var state = StarterCampaign.make()
        var engine = RulesEngine()
        let action = InterpretedAction(intent: .investigate, approach: "inspect the map", desiredOutcome: "find a hidden route")
        var random: any RandomSource = SequenceRandomSource([20])

        let result = engine.resolve(action, in: state, random: &random)

        XCTAssertTrue(result.events.contains(where: { $0.kind == .factDiscovered }))
        XCTAssertTrue(result.explanation.contains("Mira's map"))
        result.events.forEach { state.apply($0) }
        XCTAssertTrue(state.discoveredFacts.contains("Mira's map marks the Old Road as a route toward the Sunken Vault."))
    }

    func testSuccessfulQuestionRevealsNPCFact() {
        var state = StarterCampaign.make()
        var engine = RulesEngine()
        let action = InterpretedAction(intent: .persuade, targetID: "mira", approach: "ask Mira about the vault", desiredOutcome: "learn what she knows")
        var random: any RandomSource = SequenceRandomSource([20])

        let result = engine.resolve(action, in: state, random: &random)

        XCTAssertTrue(result.events.contains(where: { $0.kind == .npcDispositionChanged }))
        XCTAssertTrue(result.events.contains(where: { $0.kind == .factDiscovered && $0.text == "The duke's seal opens the vault." }))
        XCTAssertTrue(result.explanation.contains("The duke's seal opens the vault."))
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
        var original = StarterCampaign.make()
        original.recentTurns[0] = ConversationEntry(
            id: original.recentTurns[0].id,
            speaker: original.recentTurns[0].speaker,
            speakerName: original.recentTurns[0].speakerName,
            text: original.recentTurns[0].text,
            eventSummaries: original.recentTurns[0].eventSummaries,
            date: Date(timeIntervalSinceReferenceDate: 123456.789123)
        )
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

    func testProviderFallsBackWhenPrimaryIsUnavailable() async throws {
        struct UnavailableProvider: AIProvider {
            func interpret(command: PlayerCommand, context: DMContext) async throws -> InterpretedAction { throw AIProviderError.unavailable }
            func narrate(context: NarrationContext) async throws -> String { throw AIProviderError.unavailable }
            func extractMemories(context: NarrationContext) async throws -> [MemoryCandidate] { throw AIProviderError.unavailable }
        }
        let campaign = StarterCampaign.make()
        let context = ContextBuilder().build(for: campaign)
        let provider = FallbackAIProvider(primary: UnavailableProvider(), fallback: FakeAIProvider())
        let action = try await provider.interpret(command: PlayerCommand(rawText: "look around"), context: context)
        XCTAssertEqual(action.intent, .investigate)
    }

    func testFakeProviderRecognizesQuestionForNearbyNPC() async throws {
        let campaign = StarterCampaign.make()
        let context = ContextBuilder().build(for: campaign)
        let action = try await FakeAIProvider().interpret(
            command: PlayerCommand(rawText: "Ask Mira what she knows about the vault."),
            context: context
        )
        XCTAssertEqual(action.intent, .persuade)
        XCTAssertEqual(action.targetID, "mira")
    }

    func testCoopHostAuthoritativelyRejectsStaleAndDuplicateCommands() async throws {
        let initial = CoopStarterCampaign.make()
        let runtime = HostGameRuntime(state: initial, dice: ScriptedCoopDice([20]))
        let accepted = await runtime.receive(CoopPlayerIntentSubmission(campaignID: initial.campaignID, playerID: CoopStarterCampaign.hostPlayerID, baseRevision: 0, text: "inspect the bell"))
        XCTAssertTrue(accepted.accepted)
        XCTAssertFalse(accepted.events.isEmpty)

        let duplicateID = UUID()
        let nextRevision = accepted.projection.revision
        let first = await runtime.receive(CoopPlayerIntentSubmission(commandID: duplicateID, campaignID: initial.campaignID, playerID: CoopStarterCampaign.hostPlayerID, baseRevision: nextRevision, text: "inspect the bell"))
        let duplicate = await runtime.receive(CoopPlayerIntentSubmission(commandID: duplicateID, campaignID: initial.campaignID, playerID: CoopStarterCampaign.hostPlayerID, baseRevision: nextRevision, text: "inspect the bell"))
        XCTAssertTrue(first.accepted)
        XCTAssertTrue(duplicate.duplicate)
        XCTAssertEqual(first.events, duplicate.events)

        let stale = await runtime.receive(CoopPlayerIntentSubmission(campaignID: initial.campaignID, playerID: CoopStarterCampaign.hostPlayerID, baseRevision: 0, text: "inspect again"))
        XCTAssertFalse(stale.accepted)
        XCTAssertTrue(stale.reason?.contains("out of date") == true)
    }

    func testCoopProjectionFiltersPrivateAudienceAtSerializationBoundary() throws {
        let initial = CoopStarterCampaign.make()
        let otherPlayer = UUID()
        let privateEvent = CommittedCoopEvent(sequence: 1, audience: .players([CoopStarterCampaign.hostPlayerID]), payload: .privateObservation(text: "Only the host can see this clue.", playerID: CoopStarterCampaign.hostPlayerID))
        let hostProjection = CoopStateProjection(state: initial, playerID: CoopStarterCampaign.hostPlayerID, events: [privateEvent])
        let otherProjection = CoopStateProjection(state: initial, playerID: otherPlayer, events: [privateEvent])
        XCTAssertEqual(hostProjection.visibleEvents.count, 1)
        XCTAssertTrue(otherProjection.visibleEvents.isEmpty)
        let encoded = try JSONEncoder().encode(otherProjection)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("Only the host can see this clue."))
    }

    func testCoopJournalReplaysCommittedEvents() throws {
        let initial = CoopStarterCampaign.make()
        let event = CommittedCoopEvent(sequence: 1, payload: .worldFactDiscovered(fact: "The bell is bound to the shrine."))
        let replayed = try CoopReplay.apply([event], to: initial)
        XCTAssertEqual(replayed.revision, 1)
        XCTAssertTrue(replayed.world.facts.contains("The bell is bound to the shrine."))
    }

    func testCoopCharacterClaimIsExplicitAndSingleOwner() async throws {
        let initial = CoopStarterCampaign.make()
        let runtime = HostGameRuntime(state: initial)
        let playerID = (try await runtime.registerPlayer(displayName: "Rin", peerID: "rin-device")).id
        _ = try await runtime.approve(playerID: playerID, peerID: "rin-device")
        _ = try await runtime.claimCharacter(playerID: playerID, characterID: CoopStarterCampaign.companionCharacterID)
        let snapshot = await runtime.snapshot()
        XCTAssertEqual(snapshot.party.characters[CoopStarterCampaign.companionCharacterID]?.ownerID, playerID)
        do {
            _ = try await runtime.claimCharacter(playerID: CoopStarterCampaign.hostPlayerID, characterID: CoopStarterCampaign.companionCharacterID)
            XCTFail("A claimed character must not be claimable by another player.")
        } catch {
            XCTAssertTrue(error is CoopRuntimeError)
        }
    }
}
