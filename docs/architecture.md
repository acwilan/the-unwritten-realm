# Architecture decisions

## Canonical state is a Codable value

`CampaignState` is the authoritative world snapshot. SwiftUI observes it but does not own it. The state contains player data, locations, NPCs, quests, discovered facts, recent conversation, and an append-only event log.

## Events are the mutation boundary

`RulesEngine` produces `GameEvent` values. `CampaignState.apply` is the only mutation path used by turn execution. Narration can fail after events are applied; a fallback sentence is shown and the resolved state is still saved, avoiding duplicate rolls on retry.

## AI is behind a small application boundary

`AIProvider` exposes only interpretation, narration, and optional memory candidates. `FakeAIProvider` enables deterministic development and tests. `FoundationModelsAIProvider` is isolated to `DM/AIProvider.swift`, so Apple-specific APIs do not leak into Game Core.

## Context is permissioned

`ContextBuilder` constructs a compact `DMContext` from the current location, nearby NPCs, recent turns, active quest, and selected facts. NPC context includes `knownFacts` but intentionally excludes `secrets`; secrets remain canonical state until a future explicit revelation event.

## Persistence is replaceable and versioned

`CampaignStore` separates storage from the domain. The initial implementation writes a JSON `CampaignState` with `schemaVersion` to Application Support. No Foundation Models runtime object is persisted.

## Godot migration boundary

The future frontend can call the same application-facing concepts already used by SwiftUI: create/load a campaign, submit a `PlayerCommand`, receive `GameTurnResult`, inspect `CampaignState`, and react to explicit `GameEvent` values. No game rule depends on a SwiftUI view.
