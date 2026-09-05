import SwiftUI

struct ContentView: View {
    @ObservedObject var session: GameSession
    @State private var draft = ""
    @State private var showingJournal = false
    @State private var showingNewCampaignConfirmation = false
    @FocusState private var inputIsFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color(.systemBackground).ignoresSafeArea()

                Group {
                    if let campaign = session.campaign {
                        adventureView(campaign)
                    } else {
                        welcomeView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationTitle("The Unwritten Realm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if session.campaign != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Journal", systemImage: "book.closed") { showingJournal = true }
                            Button("New Campaign", systemImage: "plus.circle", role: .destructive) { showingNewCampaignConfirmation = true }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { inputIsFocused = false }
                    }
                }
            }
            .sheet(isPresented: $showingJournal) {
                if let campaign = session.campaign { JournalView(campaign: campaign) }
            }
            .confirmationDialog("Start a new campaign?", isPresented: $showingNewCampaignConfirmation) {
                Button("Start New Campaign", role: .destructive) { session.startNewCampaign() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Your current campaign will be replaced on this device.") }
            .alert("Something went wrong", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
                Button("OK") { session.errorMessage = nil }
            } message: { Text(session.errorMessage ?? "") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var welcomeView: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "moon.stars.fill").font(.system(size: 64)).foregroundStyle(.indigo)
            Text("The Moon Beneath the Hill").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("A living story where your words become the next move.").font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Begin Adventure", systemImage: "play.fill") { session.startNewCampaign() }.buttonStyle(.borderedProminent)
            Spacer()
        }.padding(28)
    }

    private func adventureView(_ campaign: CampaignState) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if let location = campaign.currentLocation {
                            Text(location.description).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
                            if !location.exits.isEmpty {
                                Text("Paths: " + location.exits.compactMap { campaign.locations[$0]?.name }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                            }
                        }
                        ForEach(campaign.recentTurns) { entry in
                            MessageBubble(entry: entry)
                        }
                        if session.isProcessing {
                            HStack { ProgressView(); Text("The Dungeon Master is thinking…").foregroundStyle(.secondary) }.padding()
                        }
                    }.padding(.vertical)
                }
                .onChange(of: campaign.recentTurns.count) { _, _ in
                    if let last = campaign.recentTurns.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let check = session.lastCheck { Text("Last check · \(check.label)").font(.caption).foregroundStyle(.secondary).padding(.bottom, 5) }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("What do you do?", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($inputIsFocused)
                Button {
                    let value = draft
                    draft = ""
                    inputIsFocused = false
                    session.submit(value)
                } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                .disabled(session.isProcessing || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { inputIsFocused = false }
    }
}

private struct MessageBubble: View {
    let entry: ConversationEntry
    var body: some View {
        HStack {
            if entry.speaker == .player { Spacer(minLength: 35) }
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.speaker == .player ? "You" : (entry.speakerName ?? "Dungeon Master")).font(.caption.bold()).foregroundStyle(entry.speaker == .player ? .indigo : .secondary)
                Text(entry.text)
                if !entry.eventSummaries.isEmpty { Text(entry.eventSummaries.joined(separator: "  ")).font(.caption2).foregroundStyle(.secondary) }
            }.padding(12).background(entry.speaker == .player ? Color.indigo.opacity(0.12) : Color.secondary.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 14))
            if entry.speaker != .player { Spacer(minLength: 20) }
        }.padding(.horizontal)
    }
}

private struct JournalView: View {
    let campaign: CampaignState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Character") {
                    LabeledContent("Health", value: "\(campaign.player.hitPoints) / \(campaign.player.maxHitPoints)")
                    ForEach(Attribute.allCases, id: \.self) { attribute in LabeledContent(attribute.rawValue.capitalized, value: "\(campaign.player.attributes[attribute, default: 0]) (\(campaign.player.modifier(for: attribute) >= 0 ? "+" : "")\(campaign.player.modifier(for: attribute)))") }
                }
                Section("Inventory") {
                    ForEach(campaign.player.inventory) { item in VStack(alignment: .leading) { Text(item.name); Text(item.description).font(.caption).foregroundStyle(.secondary) } }
                }
                if let quest = campaign.activeQuest { Section("Quest") { Text(quest.title).font(.headline); Text(quest.objective); Text(quest.summary).font(.caption).foregroundStyle(.secondary) } }
                Section("Current location") { Text(campaign.currentLocation?.name ?? "Unknown"); Text("\(campaign.minutesElapsed) minutes elapsed").font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("Journal").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
