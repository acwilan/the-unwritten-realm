import Foundation

public enum StarterCampaign {
    public static func make(profile: CharacterCreationProfile = .default, difficulty: CampaignDifficulty = .easy,
                            language: AppLanguage = .english) -> CampaignState {
        func l(_ key: String) -> String { AppLocalization.string(key, language: language) }

        let locations = [
            "tavern": Location(id: "tavern", name: l("The Lantern & Lark"), description: l("A warm, crowded tavern where rain ticks against the shutters."), exits: ["square", "blacksmith"], npcIDs: ["mira", "brom"]),
            "square": Location(id: "square", name: l("Village Square"), description: l("A rain-dark square dominated by a dry fountain and a watch post."), exits: ["tavern", "old_road", "forest_path"], npcIDs: ["elian"]),
            "blacksmith": Location(id: "blacksmith", name: l("Ash & Anvil"), description: l("A low forge glowing orange beneath a soot-black roof."), exits: ["tavern", "square"], npcIDs: ["nessa"]),
            "old_road": Location(id: "old_road", name: l("The Old Road"), description: l("Broken milestones lead east toward a chapel swallowed by ivy."), exits: ["square", "chapel"], npcIDs: []),
            "chapel": Location(id: "chapel", name: l("Ruined Chapel"), description: l("Moonlight enters through a collapsed roof. An empty reliquary waits beneath the altar."), exits: ["old_road", "dungeon"], npcIDs: []),
            "forest_path": Location(id: "forest_path", name: l("Forest Path"), description: l("A narrow path winds through dripping pines toward a rope bridge."), exits: ["square", "goblin_bridge"], npcIDs: []),
            "goblin_bridge": Location(id: "goblin_bridge", name: l("Goblin Bridge"), description: l("A rope bridge spans a ravine. A small goblin watches from a barrel of warning bells."), exits: ["forest_path", "dungeon"], npcIDs: ["vek"]),
            "dungeon": Location(id: "dungeon", name: l("The Sunken Vault"), description: l("A stone stair descends into blue darkness. The old duke's seal is carved into the door."), exits: ["chapel", "goblin_bridge"], npcIDs: [])
        ]
        let npcs = [
            "mira": NPC(id: "mira", name: "Mira Vale", role: l("runaway cartographer and companion"), personality: [l("dryly brave"), l("observant")], goal: l("Find the map her missing brother left in the Sunken Vault."), disposition: 25, knownFacts: [l("The duke's seal opens the vault.")], secrets: [l("She once worked for the duke's spies.")], emotionalState: l("watchful"), locationID: "tavern"),
            "brom": NPC(id: "brom", name: "Brom", role: l("traveling merchant"), personality: [l("boisterous"), l("superstitious")], goal: l("Sell his wares before the road closes."), disposition: 5, knownFacts: [l("A goblin called Vek guards the forest bridge.")], secrets: [l("His best compass is counterfeit.")], emotionalState: l("cheerful"), locationID: "tavern"),
            "elian": NPC(id: "elian", name: l("Captain Elian"), role: l("village guard captain"), personality: [l("formal"), l("tired")], goal: l("Keep danger out of the village."), disposition: 0, knownFacts: [l("The old road is currently open.")], secrets: [l("He has not been paid in three months.")], emotionalState: l("suspicious"), locationID: "square"),
            "nessa": NPC(id: "nessa", name: "Nessa Flint", role: l("blacksmith"), personality: [l("blunt"), l("kind")], goal: l("Keep the village supplied."), disposition: 15, knownFacts: [l("The chapel altar has a hidden mechanism.")], secrets: [], emotionalState: l("focused"), locationID: "blacksmith"),
            "vek": NPC(id: "vek", name: l("Vek-of-the-Bells"), role: l("goblin bridge keeper"), personality: [l("clever"), l("easily bored")], goal: l("Make travelers answer the bridge's riddle."), disposition: -10, knownFacts: [l("The vault entrance can be reached from this ravine.")], secrets: [l("Vek is afraid of the bridge bells.")], emotionalState: l("amused"), locationID: "goblin_bridge")
        ]
        let player = PlayerCharacter(name: profile.name, level: 1,
                                     hitPoints: profile.type.startingHitPoints,
                                     maxHitPoints: profile.type.startingHitPoints,
                                     attributes: profile.type.startingAttributes,
                                     inventory: [
                                        Item(id: "rope", name: l("Coil of rope"), description: l("Useful for climbing, tying, or improvising."), usable: false),
                                        Item(id: "healing_potion", name: l("Healing potion"), description: l("Restores a little health."), usable: true),
                                        Item(id: "old_coin", name: l("Old silver coin"), description: l("Stamped with a crescent moon."), usable: false)
                                     ], characterType: profile.type, abilities: profile.abilities)
        return CampaignState(title: "The Moon Beneath the Hill", language: language, difficulty: difficulty, player: player, currentLocationID: "tavern",
                             locations: locations, npcs: npcs, quests: [
                                "moon_vault": Quest(id: "moon_vault", title: l("The Moon Beneath the Hill"), summary: l("Reach the Sunken Vault before the trail goes cold."), status: .active, objective: l("Find a way into the Sunken Vault."))
                             ], recentTurns: [ConversationEntry(speaker: .narrator, text: l("Rain whispers over the Lantern & Lark. Mira Vale slides a damp map across the table. ‘The vault is real,’ she says. ‘And someone is already looking for it.’"))])
    }
}
