# The Unwritten Realm

The Unwritten Realm is a native iOS text adventure. You describe what your character does in ordinary language, the game interprets your intent, and a deterministic rules engine resolves the consequences before the Dungeon Master narrates what happens next.

## Local co-op

Local co-op is a separate mode from the original single-player campaign. From the home screen (or the campaign menu), choose **Local Co-op**. On one iPhone or iPad, choose **Host a co-op campaign**; on each other device, choose **Find a nearby host**, select the host, wait for approval, and choose an unclaimed character. One iPhone or iPad hosts **The Bell Beneath the Inn** through Multipeer Connectivity. The host owns the authoritative co-op state, dice, event journal, and rules resolution. Clients submit text intentions and receive audience-filtered projections.

The host and all approved players should remain in the co-op story view while playing. **Leave** exits only the current device; **End Session** on the host disconnects all players and returns each device to its previous campaign. The host automatically synchronizes the latest campaign projection to every approved player after each action.

The co-op core is intentionally independent of the existing single-player `CampaignState`: `HostGameRuntime` serializes commands, `CoopCampaignState` is replayable from typed events, `CoopStateProjection` removes unauthorized event data before encoding, and `JSONCoopCampaignJournalStore` provides a snapshot/journal seam for recovery. Simulator and unit-test paths use the loopback transport; nearby-device verification requires two physical devices with local networking permission enabled.

## End-user guide

### Languages

The app supports English, Spanish, Portuguese, French, German, and Italian. Language selection follows Apple's standard order: the language configured for this app in iOS Settings, the OS's preferred language, then English. To choose a language, open **Settings > Apps > The Unwritten Realm > Language** on iOS.

Translations live in `TheUnwrittenRealm/Localization/<language>.lproj/Localizable.strings`. To add a language, add its locale code to `AppLanguage`, create the matching `.lproj` file, add that file to the `Localizable.strings` variant group in the Xcode project, and add the locale to `knownRegions`. SwiftUI labels use the English key as the fallback, while `AppLocalization` is used for formatted strings and copy resolved outside a view.

### Start an adventure

1. Open The Unwritten Realm.
2. Tap **Create Your Character**.
3. Choose a name, type, up to two signature abilities, and a difficulty.
4. Read the setting, story, and opening scene in the introduction.
5. Read the opening scene and the available paths at your current location.

Your campaign is saved on the device. If a saved campaign exists, the app opens it when you return.

### Describe what you want to do

Type an action in **What do you do?** and tap the arrow button. Use natural language and be specific about your intent. For example:

- `Ask Mira what she knows about the vault.`
- `Inspect the map for a hidden route.`
- `Travel to the village square.`
- `Use the healing potion.`
- `Rest by the fire.`

The game may ask for an ability check. The result, including critical successes and failures, becomes part of the story and changes the campaign state when appropriate.

Campaign difficulty changes the target values for ability checks and attacks. **Easy** lowers targets by 2; **Difficult** raises them by 2. Natural 1s and natural 20s remain critical outcomes in either mode. Co-op hosts choose the difficulty before starting the session, and all players receive it as part of the authoritative campaign state.

### Explore the world

The current location shows its description and the paths connected to it. Travel is limited to those displayed paths, so try investigating, talking to nearby characters, or using an item when a destination is not directly reachable.

You can attempt actions such as:

- exploring or investigating places and objects;
- persuading, deceiving, helping, or confronting characters;
- traveling between connected locations;
- using items from your inventory; and
- resting to recover or let time pass.

The world’s rules are authoritative. A narration can describe the result, but it cannot invent an item, reveal a private secret, or move you somewhere you cannot reach.

### Check your journal

Tap the **•••** menu in the top-right corner and choose **Journal** to review:

- current health and ability scores;
- character type and signature abilities;
- your inventory;
- the active quest and objective; and
- your current location and elapsed time.

The same menu lets you start a new campaign. Starting a new campaign replaces the current campaign saved on that device.

### Saving and AI behavior

The app saves the campaign after starting it and after each completed turn. The on-device Apple Foundation Models provider is used when available. On the Simulator, unsupported devices, and during tests, the app uses a deterministic fallback so the adventure remains playable.

For build instructions, tests, project structure, and development conventions, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Publish to TestFlight

The **Publish iOS to TestFlight** GitHub Actions workflow archives the app for a physical iOS device and uploads the IPA to App Store Connect. It never runs tests or starts a simulator. Run it manually from the Actions tab, or push a tag matching `v*`.

Configure these GitHub Actions values before running it:

- Variables: `APPSTORE_ISSUER_ID` and `APPSTORE_API_KEY_ID`.
- Secrets: `APPSTORE_API_PRIVATE_KEY`, `APPSTORE_CERTIFICATES_FILE_BASE64`, and `APPSTORE_CERTIFICATES_PASSWORD`.

The certificate secret must contain an Apple Distribution `.p12` encoded with base64. The App Store Connect API key should have permission to upload builds, and the provisioning profile must be an App Store profile for `com.acwilan.TheUnwrittenRealm` named `AppStore com.acwilan.TheUnwrittenRealm`.
