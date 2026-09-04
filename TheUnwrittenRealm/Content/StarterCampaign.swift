import Foundation

public enum StarterCampaign {
    public static func make() -> CampaignState {
        let locations = [
            "tavern": Location(id: "tavern", name: "The Lantern & Lark", description: "A warm, crowded tavern where rain ticks against the shutters.", exits: ["square", "blacksmith"], npcIDs: ["mira", "brom"]),
            "square": Location(id: "square", name: "Village Square", description: "A rain-dark square dominated by a dry fountain and a watch post.", exits: ["tavern", "old_road", "forest_path"], npcIDs: ["elian"]),
            "blacksmith": Location(id: "blacksmith", name: "Ash & Anvil", description: "A low forge glowing orange beneath a soot-black roof.", exits: ["tavern", "square"], npcIDs: ["nessa"]),
            "old_road": Location(id: "old_road", name: "The Old Road", description: "Broken milestones lead east toward a chapel swallowed by ivy.", exits: ["square", "chapel"], npcIDs: []),
            "chapel": Location(id: "chapel", name: "Ruined Chapel", description: "Moonlight enters through a collapsed roof. An empty reliquary waits beneath the altar.", exits: ["old_road", "dungeon"], npcIDs: []),
            "forest_path": Location(id: "forest_path", name: "Forest Path", description: "A narrow path winds through dripping pines toward a rope bridge.", exits: ["square", "goblin_bridge"], npcIDs: []),
            "goblin_bridge": Location(id: "goblin_bridge", name: "Goblin Bridge", description: "A rope bridge spans a ravine. A small goblin watches from a barrel of warning bells.", exits: ["forest_path", "dungeon"], npcIDs: ["vek"]),
            "dungeon": Location(id: "dungeon", name: "The Sunken Vault", description: "A stone stair descends into blue darkness. The old duke's seal is carved into the door.", exits: ["chapel", "goblin_bridge"], npcIDs: [])
        ]
        let npcs = [
            "mira": NPC(id: "mira", name: "Mira Vale", role: "runaway cartographer and companion", personality: ["dryly brave", "observant"], goal: "Find the map her missing brother left in the Sunken Vault.", disposition: 25, knownFacts: ["The duke's seal opens the vault."], secrets: ["She once worked for the duke's spies."], emotionalState: "watchful", locationID: "tavern"),
            "brom": NPC(id: "brom", name: "Brom", role: "traveling merchant", personality: ["boisterous", "superstitious"], goal: "Sell his wares before the road closes.", disposition: 5, knownFacts: ["A goblin called Vek guards the forest bridge."], secrets: ["His best compass is counterfeit."], emotionalState: "cheerful", locationID: "tavern"),
            "elian": NPC(id: "elian", name: "Captain Elian", role: "village guard captain", personality: ["formal", "tired"], goal: "Keep danger out of the village.", disposition: 0, knownFacts: ["The old road is currently open."], secrets: ["He has not been paid in three months."], emotionalState: "suspicious", locationID: "square"),
            "nessa": NPC(id: "nessa", name: "Nessa Flint", role: "blacksmith", personality: ["blunt", "kind"], goal: "Keep the village supplied.", disposition: 15, knownFacts: ["The chapel altar has a hidden mechanism."], secrets: [], emotionalState: "focused", locationID: "blacksmith"),
            "vek": NPC(id: "vek", name: "Vek-of-the-Bells", role: "goblin bridge keeper", personality: ["clever", "easily bored"], goal: "Make travelers answer the bridge's riddle.", disposition: -10, knownFacts: ["The vault entrance can be reached from this ravine."], secrets: ["Vek is afraid of the bridge bells."], emotionalState: "amused", locationID: "goblin_bridge")
        ]
        let player = PlayerCharacter(name: "Wayfarer", level: 1, hitPoints: 10, maxHitPoints: 10,
                                     attributes: [.might: 11, .finesse: 12, .insight: 13, .presence: 12],
                                     inventory: [
                                        Item(id: "rope", name: "Coil of rope", description: "Useful for climbing, tying, or improvising.", usable: false),
                                        Item(id: "healing_potion", name: "Healing potion", description: "Restores a little health.", usable: true),
                                        Item(id: "old_coin", name: "Old silver coin", description: "Stamped with a crescent moon.", usable: false)
                                     ])
        return CampaignState(title: "The Moon Beneath the Hill", player: player, currentLocationID: "tavern",
                             locations: locations, npcs: npcs, quests: [
                                "moon_vault": Quest(id: "moon_vault", title: "The Moon Beneath the Hill", summary: "Reach the Sunken Vault before the trail goes cold.", status: .active, objective: "Find a way into the Sunken Vault.")
                             ], recentTurns: [ConversationEntry(speaker: .narrator, text: "Rain whispers over the Lantern & Lark. Mira Vale slides a damp map across the table. ‘The vault is real,’ she says. ‘And someone is already looking for it.’")])
    }
}
