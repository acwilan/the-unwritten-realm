# Local co-op architecture decisions

This repository is still a small single-target SwiftUI application, so the first vertical slice keeps the existing single-player campaign and adds a separate `Coop` boundary rather than forcing a risky rewrite. The files under `TheUnwrittenRealm/Coop` are arranged as transport-independent domain/runtime, transport, persistence, and UI seams; they can become Swift packages when the client count grows.

## ADR-001: Host-authoritative multiplayer

`HostGameRuntime` is an actor. Only it owns `CoopCampaignState`, validates claims and commands, rolls dice, and commits events. Clients send `CoopPlayerIntentSubmission` values.

## ADR-002: Event-driven state with snapshots

`CoopGameEvent` is the mutation boundary. `CoopCampaignState.reduced(by:)` is pure and `CoopReplay` replays committed events after a snapshot. `JSONCoopCampaignJournalStore` keeps the snapshot and JSONL journal separate.

## ADR-003: AI proposal boundary

`CoopIntentInterpreting` returns a constrained `CoopActionProposal`. `AIProviderCoopInterpreter` and `AIProviderCoopNarrator` adapt the existing Foundation Models boundary; deterministic interpreter/narrator implementations remain the test/runtime fallback without exposing model sessions to state or persistence.

## ADR-004: Nearby transport

`MultipeerGameTransport` implements the `CoopGameTransport` seam with reliable delivery for commands and projections. `LoopbackCoopTransport` exercises the same message bytes without devices.

## ADR-005: Relative-zone spatial model

Co-op scenes use named exits and `RelativeZone` rather than an invisible grid. Rules validate adjacency and actor reachability.

## ADR-006: Server-side audience projections

`CoopStateProjection` filters event audiences and keeps private observations out of serialized client payloads. Hidden state is not sent to the client for the UI to hide.

## ADR-007: Separate native co-op mode

The existing single-player campaign remains available. The co-op mode has a distinct starter campaign, party ownership, host lobby, and projection model so both experiences can evolve independently.

## Deferred by design

Internet relay, host election, full encounter authoring, Keychain identity, and device lifecycle testing remain follow-up work requiring physical-device or service infrastructure. The protocol and store types leave seams for those additions without implementing them in the MVP.
