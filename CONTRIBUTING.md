# Contributing

This document covers local development of The Unwritten Realm. For how to play the app, see [README.md](README.md).

## Prerequisites

- Xcode 26 or later
- An iOS 26 SDK and an available iOS Simulator for running tests

The project is an Xcode project with no external package dependencies.

## Build and run

Open `TheUnwrittenRealm.xcodeproj` in Xcode 26, select the **TheUnwrittenRealm** scheme, and run it on an iOS 26 Simulator or device.

The equivalent command-line build is:

```sh
xcodebuild -project TheUnwrittenRealm.xcodeproj \
  -scheme TheUnwrittenRealm \
  -sdk iphonesimulator \
  build
```

Run the unit tests with:

```sh
xcodebuild -project TheUnwrittenRealm.xcodeproj \
  -scheme TheUnwrittenRealm \
  -sdk iphonesimulator \
  test
```

GitHub Actions runs the device build and unit tests on a `macos-26` runner with Xcode 26.6. The test job selects an available iOS Simulator at runtime.

## Project structure

- `TheUnwrittenRealm/Core`: Codable campaign state, rules, and explicit game events. This layer has no SwiftUI or Foundation Models dependency.
- `TheUnwrittenRealm/Application`: turn orchestration and the game-facing session API.
- `TheUnwrittenRealm/DM`: context shaping, the deterministic fake AI, and the Apple Foundation Models adapter.
- `TheUnwrittenRealm/Persistence`: versioned JSON save/load boundary.
- `TheUnwrittenRealm/Presentation`: SwiftUI views that render state and submit `PlayerCommand` values.
- `TheUnwrittenRealmTests`: unit tests for rules, context permissions, persistence, turn execution, and provider fallback behavior.
- `docs/architecture.md`: the deeper architecture decisions and migration boundaries.

## Development conventions

The game engine owns reality. Model output is interpreted input or narration and must never directly mutate canonical state. Rules produce explicit `GameEvent` values, and `CampaignState.apply` is the mutation boundary.

Keep AI-specific code behind `AIProvider`, keep persistence behind `CampaignStore`, and prefer deterministic providers and injected randomness in tests. When changing persisted data, preserve the schema-version boundary and add a round-trip or migration test.
