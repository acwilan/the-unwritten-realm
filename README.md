# The Unwritten Realm

The Unwritten Realm is a small native SwiftUI text-adventure MVP. The player writes arbitrary actions; an interpreter classifies the intent, the deterministic game core resolves it, and a Dungeon Master provider narrates the result.

## Build and run

Open `TheUnwrittenRealm.xcodeproj` in Xcode 26 or build from the command line:

```sh
xcodebuild -project TheUnwrittenRealm.xcodeproj -scheme TheUnwrittenRealm -sdk iphonesimulator build
xcodebuild -project TheUnwrittenRealm.xcodeproj -scheme TheUnwrittenRealm -sdk iphonesimulator test
```

The app targets iOS 26. Foundation Models is used when available; the app falls back to the deterministic `FakeAIProvider` on unsupported devices or during tests. A campaign is stored as JSON in Application Support.

GitHub Actions runs the device build and unit tests on the `macos-26` runner with Xcode 26.6. The test job discovers an available iOS Simulator at runtime.

## Structure

- `Core`: Codable campaign state, rules, and explicit game events. It has no SwiftUI or Foundation Models dependency.
- `Application`: turn orchestration and the game-facing session API.
- `DM`: context shaping, fake AI, and the Apple Foundation Models adapter.
- `Persistence`: versioned JSON save/load boundary.
- `Presentation`: SwiftUI only; it renders state and submits `PlayerCommand` values.

The game engine owns reality. Model output is interpreted input or narration and never directly mutates canonical state.
