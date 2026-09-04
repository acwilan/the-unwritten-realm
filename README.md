# The Unwritten Realm

The Unwritten Realm is a native iOS text adventure. You describe what your character does in ordinary language, the game interprets your intent, and a deterministic rules engine resolves the consequences before the Dungeon Master narrates what happens next.

## End-user guide

### Start an adventure

1. Open The Unwritten Realm.
2. Tap **Begin Adventure**.
3. Read the opening scene and the available paths at your current location.

Your campaign is saved on the device. If a saved campaign exists, the app opens it when you return.

### Describe what you want to do

Type an action in **What do you do?** and tap the arrow button. Use natural language and be specific about your intent. For example:

- `Ask Mira what she knows about the vault.`
- `Inspect the map for a hidden route.`
- `Travel to the village square.`
- `Use the healing potion.`
- `Rest by the fire.`

The game may ask for an ability check. The result, including critical successes and failures, becomes part of the story and changes the campaign state when appropriate.

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
- your inventory;
- the active quest and objective; and
- your current location and elapsed time.

The same menu lets you start a new campaign. Starting a new campaign replaces the current campaign saved on that device.

### Saving and AI behavior

The app saves the campaign after starting it and after each completed turn. The on-device Apple Foundation Models provider is used when available. On the Simulator, unsupported devices, and during tests, the app uses a deterministic fallback so the adventure remains playable.

For build instructions, tests, project structure, and development conventions, see [CONTRIBUTING.md](CONTRIBUTING.md).
