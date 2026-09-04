import Foundation

public struct ContextBuilder: Sendable {
    public init() {}

    public func build(for state: CampaignState, actionText: String? = nil) -> DMContext {
        let location = state.currentLocation ?? Location(id: "unknown", name: "Unknown", description: "", exits: [], npcIDs: [])
        let npcs = location.npcIDs.compactMap { state.npcs[$0] }.map { npc in
            NPCContext(id: npc.id, name: npc.name, role: npc.role, personality: npc.personality,
                       disposition: npc.disposition, knownFacts: npc.knownFacts,
                       memories: Array(npc.memories.sorted { $0.importance > $1.importance }.prefix(3)))
        }
        return DMContext(location: location, player: state.player, nearbyNPCs: npcs,
                         activeQuest: state.activeQuest, relevantFacts: Array(state.discoveredFacts.suffix(8)),
                         recentConversation: Array(state.recentTurns.suffix(8)))
    }
}
