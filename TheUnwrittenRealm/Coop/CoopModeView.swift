import SwiftUI

public struct CoopModeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = CoopModeSession()
    @State private var draft = ""
    @State private var showingLobby = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if session.projection == nil { lobby }
                else { story }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if case .unavailable(let reason) = session.foundationModelAvailability {
                    Label("Host AI unavailable · deterministic fallback active", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).padding(.horizontal).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.1))
                        .accessibilityLabel("On-device AI unavailable. \(reason)")
                }
            }
            .navigationTitle("Local Co-op")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { session.stop(); dismiss() } } }
            .alert("Co-op", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
                Button("OK") { session.errorMessage = nil }
            } message: { Text(session.errorMessage ?? "") }
        }
    }

    private var lobby: some View {
        List {
            Section {
                Text("Each player joins with their own device. One player hosts the authoritative campaign and approves every connection.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Start") {
                Button("Host a co-op campaign", systemImage: "antenna.radiowaves.left.and.right") { session.host() }
                Button("Find a nearby host", systemImage: "magnifyingglass") { session.browse() }
            }
            if session.isBrowsing && !session.discoveredPeers.isEmpty {
                Section("Nearby games") {
                    ForEach(session.discoveredPeers, id: \.self) { peer in
                        Button { session.invite(peer) } label: { Label(peer, systemImage: "gamecontroller") }
                    }
                }
            } else if session.isBrowsing {
                Section { ProgressView("Looking for nearby hosts…") }
            }
            if session.isHost && !session.pendingPlayers.isEmpty {
                Section("Join requests") {
                    ForEach(Array(session.pendingPlayers.keys), id: \.self) { playerID in
                        HStack {
                            Text(session.pendingPlayers[playerID] ?? "Player")
                            Spacer()
                            Button("Approve") { session.approve(playerID) }.buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
    }

    private var story: some View {
        VStack(spacing: 0) {
            if let projection = session.projection, let scene = projection.world.scenes[projection.world.currentSceneID] {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if session.isHost && !session.pendingPlayers.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Join requests").font(.headline)
                                ForEach(Array(session.pendingPlayers.keys), id: \.self) { playerID in
                                    HStack { Text(session.pendingPlayers[playerID] ?? "Player"); Spacer(); Button("Approve") { session.approve(playerID) }.buttonStyle(.borderedProminent) }
                                }
                            }.padding().background(.blue.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        let availableCharacters = projection.party.characters.values.filter { $0.ownerID == nil }
                        if !availableCharacters.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Choose your character").font(.headline)
                                ForEach(Array(availableCharacters), id: \.id) { character in
                                    HStack {
                                        VStack(alignment: .leading) { Text(character.name); Text("HP \(character.hitPoints)/\(character.maxHitPoints)").font(.caption).foregroundStyle(.secondary) }
                                        Spacer()
                                        Button("Choose") { session.claim(character.id) }.buttonStyle(.bordered)
                                    }
                                }
                            }.padding().background(.green.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Text(scene.name).font(.title2.bold())
                        Text(scene.description).foregroundStyle(.secondary)
                        if !scene.exits.isEmpty { Text("Exits: " + scene.exits.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                        if let encounter = projection.encounter {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Initiative · Round \(encounter.round)", systemImage: "timer")
                                Text(encounter.entries.map { "\($0.actorID) (\($0.total))" }.joined(separator: "  ·  ")).font(.caption)
                            }.padding().background(.orange.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        ForEach(projection.visibleEvents.suffix(12)) { event in
                            Text(eventDescription(event.payload)).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.secondary.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }.padding()
                }
            }
            HStack {
                TextField("What does the party do?", text: $draft, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...3)
                Button { let value = draft; draft = ""; session.submit(value) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding().background(.regularMaterial)
        }
    }

    private func eventDescription(_ event: CoopGameEvent) -> String {
        switch event {
        case .playerRegistered(_, let name, _): return "\(name) requested to join."
        case .playerApproved(_, _): return "A player joined the party."
        case .characterClaimed(_, _): return "A character was claimed."
        case .actorMoved(_, let scene, _): return "The party moved toward \(scene)."
        case .rollResolved(_, _, _, let total, let reason): return "\(reason.capitalized): resolved at \(total)."
        case .damageApplied(_, let amount): return "A hit deals \(amount) damage."
        case .healingApplied(_, let amount): return "A character recovers \(amount) HP."
        case .initiativeStarted: return "The encounter begins."
        case .turnEnded(let actor, _, let round): return "Turn ended for \(actor) · round \(round)."
        case .initiativeEnded: return "The encounter ends."
        case .worldFactDiscovered(let fact): return fact
        case .narration(let text): return text
        case .privateObservation(let text, _): return text
        }
    }
}
