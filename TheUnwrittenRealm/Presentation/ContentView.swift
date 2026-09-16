import SwiftUI

struct ContentView: View {
    @ObservedObject var session: GameSession
    @Environment(\.appLanguage) private var language
    @State private var draft = ""
    @State private var showingJournal = false
    @State private var showingCoop = false
    @State private var showingNewCampaignConfirmation = false
    @State private var showingCharacterCreation = false
    @State private var showingCampaignIntro = false
    @State private var pendingCharacterProfile: CharacterCreationProfile?
    @FocusState private var inputIsFocused: Bool
    @StateObject private var speech = SpeechService()

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingJournal) {
            if let campaign = session.campaign { JournalView(campaign: campaign) }
        }
        .sheet(isPresented: $showingCoop) { CoopModeView() }
        .fullScreenCover(isPresented: $showingCharacterCreation, onDismiss: {
            guard let profile = pendingCharacterProfile else { return }
            session.startNewCampaign(profile: profile, language: language)
            pendingCharacterProfile = nil
            showingCampaignIntro = true
        }) {
            CharacterCreationView { profile in
                pendingCharacterProfile = profile
                showingCharacterCreation = false
            }
        }
        .fullScreenCover(isPresented: $showingCampaignIntro) {
            if let campaign = session.campaign {
                CampaignIntroView(campaign: campaign) { showingCampaignIntro = false }
            }
        }
        .confirmationDialog("Start a new campaign?", isPresented: $showingNewCampaignConfirmation) {
            Button("Customize Character", role: .destructive) { showingCharacterCreation = true }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your current campaign will be replaced on this device.") }
        .alert("Something went wrong", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
            Button("OK") { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
    }

    private var welcomeView: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "moon.stars.fill").font(.system(size: 64)).foregroundStyle(.indigo)
            Text("The Moon Beneath the Hill").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text("A living story where your words become the next move.").font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Create Your Character", systemImage: "person.fill.badge.plus") { showingCharacterCreation = true }.buttonStyle(.borderedProminent)
            Button("Local Co-op", systemImage: "person.3.fill") { showingCoop = true }.buttonStyle(.bordered)
            Spacer()
        }.padding(28)
    }

    private func adventureView(_ campaign: CampaignState) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("The Unwritten Realm")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Menu {
                    Button("Journal", systemImage: "book.closed") { showingJournal = true }
                    Button("Local Co-op", systemImage: "person.3.fill") { showingCoop = true }
                    Button("New Campaign", systemImage: "plus.circle", role: .destructive) { showingNewCampaignConfirmation = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                }
                .accessibilityLabel("Campaign menu")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if case .unavailable(let reason) = session.foundationModelAvailability {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("On-device AI unavailable")
                            .font(.caption.weight(.semibold))
                        Text(reason)
                            .font(.caption2)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal)
                .padding(.bottom, 6)
                .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text(AppLocalization.format("On-device AI unavailable. %@", language: language, reason)))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if let location = campaign.currentLocation {
                            Text(location.description).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
                            if !location.exits.isEmpty {
                                Text(AppLocalization.format("Paths: %@", language: language, location.exits.compactMap { campaign.locations[$0]?.name }.joined(separator: " · ")))
                                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                            }
                        }
                        ForEach(campaign.recentTurns) { entry in
                            MessageBubble(entry: entry, speech: speech)
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
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let check = session.lastCheck {
                    Text(AppLocalization.format("Last check · %@", language: language, check.label))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 5)
                }
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
                }
                .padding()
            }
            .background(.regularMaterial)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { inputIsFocused = false }
        .onDisappear { speech.stop() }
    }
}

private struct CharacterCreationView: View {
    let onComplete: (CharacterCreationProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @State private var name = ""
    @State private var selectedType: CharacterType = .vanguard
    @State private var selectedAbilities: [String] = []

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var cleanedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canBegin: Bool {
        !cleanedName.isEmpty && selectedAbilities.count <= 2
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Make the story yours")
                            .font(.largeTitle.bold())
                        Text("Choose who walks into the rain. Your choices shape the way the realm answers you.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name").font(.headline)
                        TextField("What are you called?", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose a type").font(.headline)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(CharacterType.allCases) { type in
                                Button {
                                    selectedType = type
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Image(systemName: type.icon)
                                            Spacer()
                                            if selectedType == type {
                                                Image(systemName: "checkmark.circle.fill")
                                            }
                                        }
                                        .font(.title3)
                                        Text(type.localizedDisplayName(in: language)).font(.headline)
                                        Text(type.localizedSummary(in: language))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                        Text(AppLocalization.format("Might %@ · Finesse %@ · Insight %@ · Presence %@", language: language,
                                                                    String(type.startingAttributes[.might, default: 0]),
                                                                    String(type.startingAttributes[.finesse, default: 0]),
                                                                    String(type.startingAttributes[.insight, default: 0]),
                                                                    String(type.startingAttributes[.presence, default: 0])))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                                    .padding(14)
                                    .background(selectedType == type ? Color.indigo.opacity(0.14) : Color.secondary.opacity(0.08))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(selectedType == type ? Color.indigo : .clear, lineWidth: 2)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(selectedType == type ? .indigo : .primary)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Choose abilities").font(.headline)
                            Spacer()
                            Text("\(selectedAbilities.count) / 2")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(selectedAbilities.count == 2 ? .indigo : .secondary)
                        }
                        Text("Pick up to two signature abilities. They describe your strengths and stay with your character.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        VStack(spacing: 8) {
                            ForEach(CharacterCreationProfile.availableAbilities) { ability in
                                let isSelected = selectedAbilities.contains(ability.name)
                                Button {
                                    if isSelected {
                                        selectedAbilities.removeAll { $0 == ability.name }
                                    } else if selectedAbilities.count < 2 {
                                        selectedAbilities.append(ability.name)
                                    }
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(ability.localizedName(in: language)).font(.subheadline.weight(.semibold))
                                            Text(ability.localizedDescription(in: language)).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(isSelected ? Color.indigo.opacity(0.12) : Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(isSelected ? .indigo : .primary)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Ready to enter the realm", systemImage: "sparkles")
                            .font(.headline)
                            .foregroundStyle(.indigo)
                        Text("You can discover the rest through play. There is no single right way to approach the story.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .padding(.bottom, 12)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onComplete(CharacterCreationProfile(name: cleanedName, type: selectedType, abilities: selectedAbilities))
                    dismiss()
                } label: {
                    Text("Enter the Realm")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canBegin)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
            .navigationTitle("New Campaign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct CampaignIntroView: View {
    let campaign: CampaignState
    let onContinue: () -> Void
    @Environment(\.appLanguage) private var language

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.indigo)
                        Text(AppLocalization.string(campaign.title, language: language))
                            .font(.largeTitle.bold())
                        Text("Your story begins tonight.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    IntroSection(icon: "globe.americas.fill", title: "The setting", text: "The Unwritten Realm is a rain-soaked frontier where old magic has gone quiet, but never truly disappeared. Villages cling to the edges of forests, forgotten roads lead to sealed ruins, and every person you meet has a reason to keep part of the truth hidden.")

                    IntroSection(icon: "book.closed.fill", title: "The story so far", text: "In the village of Larkspur, a vanished duke left behind a map, a crescent-marked coin, and rumors of the Sunken Vault beneath the hill. Mira Vale believes the vault holds the last trace of her missing brother. Others are searching too—and the trail is already going cold.")

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Your place in it", systemImage: campaign.player.characterType.icon)
                            .font(.headline)
                            .foregroundStyle(.indigo)
                        Text(AppLocalization.format("%@, the %@, you arrive at the Lantern & Lark with a few tools, a little history, and no promise that the night will leave you unchanged.",
                                                    language: language,
                                                    campaign.player.name,
                                                    campaign.player.characterType.localizedDisplayName(in: language).lowercased(with: language.locale)))
                        if !campaign.player.abilities.isEmpty {
                            Text(AppLocalization.format("Your strengths: %@.", language: language,
                                                        campaign.player.abilities.map { ability in
                                                            AppLocalization.string(ability, language: language)
                                                        }.joined(separator: " · ")))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.indigo.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    IntroSection(icon: "text.bubble.fill", title: "How to play", text: "Describe what you want to do in ordinary language. Talk to people, investigate places, travel along connected paths, use your items, or take a risk. The Dungeon Master interprets your intent, the rules resolve the consequences, and the world remembers what happens.")

                    if let opening = campaign.recentTurns.first?.text {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Opening scene")
                                .font(.headline)
                            Text(opening)
                                .italic()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(24)
                .padding(.bottom, 12)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onContinue()
                } label: {
                    Text("Begin the First Chapter")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
            .navigationTitle("Before You Begin")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct IntroSection: View {
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

private struct MessageBubble: View {
    let entry: ConversationEntry
    @ObservedObject var speech: SpeechService
    @Environment(\.appLanguage) private var language

    var body: some View {
        HStack {
            if entry.speaker == .player { Spacer(minLength: 35) }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.speaker == .player ? AppLocalization.string("You", language: language) : (entry.speakerName ?? AppLocalization.string("Dungeon Master", language: language)))
                        .font(.caption.bold())
                        .foregroundStyle(entry.speaker == .player ? .indigo : .secondary)
                    Spacer(minLength: 8)
                    if entry.speaker != .player {
                        Button {
                            speech.toggle(entry)
                        } label: {
                            Image(systemName: speech.isSpeaking(entry) ? "stop.fill" : "speaker.wave.2.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text(speech.isSpeaking(entry) ? AppLocalization.string("Stop speaking", language: language) : AppLocalization.string("Read aloud", language: language)))
                    }
                }
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
    @Environment(\.appLanguage) private var language
    var body: some View {
        NavigationStack {
            List {
                Section("Character") {
                    LabeledContent("Type", value: campaign.player.characterType.localizedDisplayName(in: language))
                    if !campaign.player.abilities.isEmpty {
                        LabeledContent("Abilities", value: campaign.player.abilities.joined(separator: ", "))
                    }
                    LabeledContent("Health", value: "\(campaign.player.hitPoints) / \(campaign.player.maxHitPoints)")
                    ForEach(Attribute.allCases, id: \.self) { attribute in LabeledContent(attribute.localizedDisplayName(in: language), value: "\(campaign.player.attributes[attribute, default: 0]) (\(campaign.player.modifier(for: attribute) >= 0 ? "+" : "")\(campaign.player.modifier(for: attribute)))") }
                }
                Section("Inventory") {
                    ForEach(campaign.player.inventory) { item in VStack(alignment: .leading) { Text(item.name); Text(item.description).font(.caption).foregroundStyle(.secondary) } }
                }
                if let quest = campaign.activeQuest { Section("Quest") { Text(quest.title).font(.headline); Text(quest.objective); Text(quest.summary).font(.caption).foregroundStyle(.secondary) } }
                Section("Current location") { Text(campaign.currentLocation?.name ?? AppLocalization.string("Unknown", language: language)); Text(AppLocalization.format("%@ minutes elapsed", language: language, String(campaign.minutesElapsed))).font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("Journal").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
