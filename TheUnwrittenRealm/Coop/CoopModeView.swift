import SwiftUI

public struct CoopModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @StateObject private var session = CoopModeSession()
    @State private var draft = ""
    @State private var showingEndSessionConfirmation = false
    @State private var showingJournal = false
    @State private var showingCampaignDescription = false

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
                        .accessibilityLabel(Text(AppLocalization.format("On-device AI unavailable. %@", language: language, reason)))
                }
            }
            .navigationTitle("Local Co-op")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(session.isHost ? "End Session" : "Leave") {
                        if session.isHost { showingEndSessionConfirmation = true }
                        else { leaveSession() }
                    }
                }
                if session.projection != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Journal", systemImage: "book.closed") { showingJournal = true }
                            Button("Campaign Description", systemImage: "text.book.closed") { showingCampaignDescription = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title2)
                        }
                        .accessibilityLabel("Campaign menu")
                    }
                }
            }
            .confirmationDialog("End co-op session?", isPresented: $showingEndSessionConfirmation) {
                Button("End Session", role: .destructive) { leaveSession() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All connected players will be disconnected and return to their previous campaign.")
            }
            .sheet(isPresented: $showingJournal) {
                if let projection = session.projection {
                    CoopJournalView(projection: projection, playerID: session.localPlayerID)
                }
            }
            .sheet(isPresented: $showingCampaignDescription) {
                CoopCampaignDescriptionView()
            }
            .alert("Co-op", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
                Button("OK") { session.errorMessage = nil }
            } message: { Text(session.errorMessage ?? "") }
        }
    }

    private var lobby: some View {
        List {
            Section {
                Text("Host: start the co-op campaign here. Joiners: find the host nearby, wait for approval, then choose an unclaimed character before acting.")
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
                        let localPlayerNeedsCharacter = projection.party.players[session.localPlayerID]?.characterID == nil
                        let availableCharacters = projection.party.characters.values.filter { $0.ownerID == nil }
                        if localPlayerNeedsCharacter && !availableCharacters.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Choose your character").font(.headline)
                                ForEach(Array(availableCharacters), id: \.id) { character in
                                    HStack {
                                        VStack(alignment: .leading) { Text(character.name); Text(AppLocalization.format("HP %@/%@", language: language, String(character.hitPoints), String(character.maxHitPoints))).font(.caption).foregroundStyle(.secondary) }
                                        Spacer()
                                        Button("Choose") { session.claim(character.id) }.buttonStyle(.bordered)
                                    }
                                }
                            }.padding().background(.green.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        if localPlayerNeedsCharacter && availableCharacters.isEmpty {
                            Text("Waiting for an unclaimed character.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(scene.name).font(.title2.bold())
                        Text(scene.description).foregroundStyle(.secondary)
                        if !scene.exits.isEmpty { Text(AppLocalization.format("Exits: %@", language: language, scene.exits.joined(separator: " · "))).font(.caption).foregroundStyle(.secondary) }
                        if let encounter = projection.encounter {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(AppLocalization.format("Initiative · Round %@", language: language, String(encounter.round)), systemImage: "timer")
                                Text(encounter.entries.map { "\($0.actorID) (\($0.total))" }.joined(separator: "  ·  ")).font(.caption)
                            }.padding().background(.orange.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        ForEach(projection.visibleEvents.suffix(12)) { event in
                            Text(eventDescription(event.payload)).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.secondary.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }.padding()
                }
            }
            if session.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("The Dungeon Master is thinking…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
            HStack {
                TextField(localPlayerNeedsCharacter ? "Choose a character first" : "What does the party do?", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .disabled(localPlayerNeedsCharacter)
                Button { let value = draft; draft = ""; session.submit(value) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(localPlayerNeedsCharacter || session.isProcessing || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding().background(.regularMaterial)
        }
    }

    private var localPlayerNeedsCharacter: Bool {
        session.projection?.party.players[session.localPlayerID]?.characterID == nil
    }

    private func leaveSession() {
        session.stop()
        dismiss()
    }

    private func eventDescription(_ event: CoopGameEvent) -> String {
        switch event {
        case .playerRegistered(_, let name, _): return AppLocalization.format("%@ requested to join.", language: language, name)
        case .playerApproved(_, _): return AppLocalization.string("A player joined the party.", language: language)
        case .characterClaimed(_, _): return AppLocalization.string("A character was claimed.", language: language)
        case .actorMoved(_, let scene, _): return AppLocalization.format("The party moved toward %@.", language: language, scene)
        case .rollResolved(_, _, _, let total, let reason): return AppLocalization.format("%@ resolved at %@.", language: language, reason.capitalized, String(total))
        case .damageApplied(_, let amount): return AppLocalization.format("A hit deals %@ damage.", language: language, String(amount))
        case .healingApplied(_, let amount): return AppLocalization.format("A character recovers %@ HP.", language: language, String(amount))
        case .initiativeStarted: return AppLocalization.string("The encounter begins.", language: language)
        case .turnEnded(let actor, _, let round): return AppLocalization.format("Turn ended for %@ · round %@.", language: language, actor.uuidString, String(round))
        case .initiativeEnded: return AppLocalization.string("The encounter ends.", language: language)
        case .worldFactDiscovered(let fact): return fact
        case .narration(let text): return text
        case .privateObservation(let text, _): return text
        }
    }
}

private struct CoopCampaignDescriptionView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    CoopIntroSection(
                        icon: "globe.americas.fill",
                        title: "The setting",
                        text: "The Unwritten Realm is a rain-soaked frontier where old magic has gone quiet, but never truly disappeared. Villages cling to the edges of forests, forgotten roads lead to sealed ruins, and every person you meet has a reason to keep part of the truth hidden."
                    )
                    CoopIntroSection(
                        icon: "book.closed.fill",
                        title: "The story so far",
                        text: "At the Lantern & Lark, a bell rings beneath the floorboards while rain seals the roads outside. The party has arrived at the beginning of a mystery that will unfold through your shared choices."
                    )
                    CoopIntroSection(
                        icon: "person.2.fill",
                        title: "How co-op works",
                        text: "Each player controls one character. Describe what you want the party to do in ordinary language; the host resolves the action and synchronizes the result to every approved player."
                    )
                }
                .padding(24)
            }
            .navigationTitle("Campaign Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct CoopIntroSection: View {
    let icon: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.indigo)
            Text(text)
                .foregroundStyle(.primary)
        }
    }
}

private struct CoopJournalView: View {
    let projection: CoopStateProjection
    let playerID: CoopPlayerID
    @Environment(\.dismiss) private var dismiss

    private var player: CoopPlayer? { projection.party.players[playerID] }
    private var character: CoopCharacter? {
        guard let characterID = player?.characterID else { return nil }
        return projection.party.characters[characterID]
    }
    private var sceneName: String {
        projection.world.scenes[projection.world.currentSceneID]?.name ?? projection.world.currentSceneID
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Character") {
                    LabeledContent("Name", value: character?.name ?? "No character selected")
                    if let character {
                        LabeledContent("Health", value: "\(character.hitPoints) / \(character.maxHitPoints)")
                        LabeledContent("Might", value: String(character.might))
                        LabeledContent("Finesse", value: String(character.finesse))
                        LabeledContent("Insight", value: String(character.insight))
                        LabeledContent("Presence", value: String(character.presence))
                    }
                }
                Section("Inventory") {
                    if let inventory = character?.inventory, !inventory.isEmpty {
                        ForEach(inventory, id: \.self) { Text($0) }
                    } else {
                        Text("Nothing carried")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Current location") {
                    Text(sceneName)
                }
            }
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
