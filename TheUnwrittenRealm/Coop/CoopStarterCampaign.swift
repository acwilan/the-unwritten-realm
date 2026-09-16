import Foundation

public enum CoopStarterCampaign {
    public static let hostPlayerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    public static let hostCharacterID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    public static let companionCharacterID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!

    public static func make() -> CoopCampaignState {
        let scenes: [CoopSceneID: CoopScene] = [
            "inn": CoopScene(id: "inn", name: "The Lantern & Lark", description: "Rain ticks against the shutters while a bell sounds beneath the floorboards.", exits: ["cellar"], landmarks: ["the hearth", "the innkeeper's desk"]),
            "cellar": CoopScene(id: "cellar", name: "The Cellar", description: "Barrels crowd a damp cellar. A sealed passage waits behind the oldest rack.", exits: ["inn", "passage"], landmarks: ["the old rack", "a cracked bell"]),
            "passage": CoopScene(id: "passage", name: "The Sealed Passage", description: "A narrow stone passage descends toward a shrine lit by blue fire.", exits: ["cellar", "shrine"], landmarks: ["crescent carvings"]),
            "shrine": CoopScene(id: "shrine", name: "The Underground Shrine", description: "A bell-shaped idol hangs over a circular chamber. Something moves beyond it.", exits: ["passage"], landmarks: ["the bell idol"])
        ]
        let host = CoopPlayer(id: hostPlayerID, displayName: "Host", approved: true, characterID: hostCharacterID)
        let wayfarer = CoopCharacter(id: hostCharacterID, name: "Wayfarer", ownerID: hostPlayerID, sceneID: "inn", zone: .nearby, hitPoints: 12, maxHitPoints: 12, defense: 11, might: 12, finesse: 11, insight: 12, presence: 10, inventory: ["rope", "healing_potion"])
        let companion = CoopCharacter(id: companionCharacterID, name: "Lantern Scout", sceneID: "inn", zone: .nearby, hitPoints: 9, maxHitPoints: 9, defense: 12, might: 10, finesse: 14, insight: 13, presence: 11)
        let hostActor = CoopActor(id: hostCharacterID, name: wayfarer.name, kind: .player, sceneID: "inn", zone: .nearby, hitPoints: wayfarer.hitPoints, maxHitPoints: wayfarer.maxHitPoints, defense: wayfarer.defense)
        let companionActor = CoopActor(id: companionCharacterID, name: companion.name, kind: .player, sceneID: "inn", zone: .nearby, hitPoints: companion.hitPoints, maxHitPoints: companion.maxHitPoints, defense: companion.defense)
        let bell = CoopActor(id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!, name: "Bell Wraith", kind: .hostile, sceneID: "shrine", zone: .engaged, hitPoints: 8, maxHitPoints: 8, defense: 12)
        let world = CoopWorldState(currentSceneID: "inn", scenes: scenes, actors: [hostActor.id: hostActor, companionActor.id: companionActor, bell.id: bell])
        return CoopCampaignState(party: CoopPartyState(players: [host.id: host], characters: [wayfarer.id: wayfarer, companion.id: companion], playerByCharacter: [wayfarer.id: host.id]), world: world, quests: ["bell": "Discover why the bell beneath the inn has started ringing."])
    }
}
