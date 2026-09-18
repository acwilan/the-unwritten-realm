import AVFAudio
import CarPlay
import UIKit

/// The CarPlay surface is intentionally a separate, linear flow. It never exposes
/// the co-op runtime or the free-form keyboard UI used on the phone.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private enum Screen {
        case home
        case story
        case processing
    }

    private let speech = SpeechService()
    private let voiceInput = VoiceInputService()
    private var interfaceController: CPInterfaceController?
    private var session: GameSession?
    private var screen: Screen = .home
    private var selectedType: CharacterType = .vanguard
    private var selectedAbilities: [String] = []

    private let suggestedNames = [
        "Aster", "Briar", "Cinder", "Rowan", "Sable", "Wren"
    ]

    override init() {
        super.init()
        voiceInput.onFinalTranscript = { [weak self] transcript in
            self?.submitVoiceCommand(transcript)
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: CPWindow) {
        self.interfaceController = interfaceController
        session = GameSession()
        showHome()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController,
                                  from window: CPWindow) {
        voiceInput.cancel()
        speech.stop()
        self.interfaceController = nil
        self.session = nil
    }

    private func showHome() {
        screen = .home
        var items = [newItem("New Campaign", detail: "Choose a character and begin a solo story.", icon: "plus.circle.fill") { [weak self] in
            self?.selectedAbilities = []
            self?.showCharacterType()
        }]

        items.append(newItem("DM Voice", detail: "Choose a deeper male, neutral, or warm female voice.", icon: "waveform") { [weak self] in
            self?.showVoiceSettings()
        })

        if session?.campaign != nil {
            items.append(newItem("Continue Campaign", detail: "Return to your latest Dungeon Master message.", icon: "play.fill") { [weak self] in
                self?.showStory(readLatest: false)
            })
        }

        let template = listTemplate(title: "The Unwritten Realm", sections: [
            section(items, header: "Solo Campaign")
        ])
        interfaceController?.setRootTemplate(template, animated: false, completion: nil)
    }

    private func showVoiceSettings() {
        let items = VoicePreference.allCases.map { preference in
            let selected = speech.voicePreference == preference
            return newItem("\(selected ? "✓ " : "")\(preference.displayName)", detail: "Use this voice for automatic Dungeon Master read-aloud.", icon: "waveform") { [weak self] in
                self?.speech.voicePreference = preference
                self?.showHome()
            }
        }
        let template = listTemplate(title: "DM Voice", sections: [section(items, header: "Read aloud")])
        interfaceController?.setRootTemplate(template, animated: true, completion: nil)
    }

    private func showCharacterType() {
        let items = CharacterType.allCases.map { type in
            let item = CPListItem(text: type.displayName, detailText: type.summary, image: UIImage(systemName: type.icon))
            item.handler = { [weak self] _, completion in
                self?.selectedType = type
                self?.showAbilities()
                completion()
            }
            return item
        }

        let template = listTemplate(title: "1 of 3 · Type", sections: [
            section(items, header: "Choose your role")
        ])
        interfaceController?.setRootTemplate(template, animated: true, completion: nil)
    }

    private func showAbilities() {
        let abilityItems = CharacterCreationProfile.availableAbilities.map { ability in
            let selected = selectedAbilities.contains(ability.name)
            let item = CPListItem(
                text: "\(selected ? "✓ " : "")\(ability.name)",
                detailText: ability.description,
                image: UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
            )
            item.handler = { [weak self] _, completion in
                guard let self else { completion(); return }
                if self.selectedAbilities.contains(ability.name) {
                    self.selectedAbilities.removeAll { $0 == ability.name }
                } else if self.selectedAbilities.count < 2 {
                    self.selectedAbilities.append(ability.name)
                }
                self.showAbilities()
                completion()
            }
            return item
        }

        let next = newItem("Next", detail: "Pick a name for your character.", icon: "arrow.right.circle.fill") { [weak self] in
            self?.showName()
        }
        let selectedSummary = selectedAbilities.isEmpty ? "Choose up to two signature abilities." : selectedAbilities.joined(separator: " · ")
        let template = listTemplate(title: "2 of 3 · Abilities", sections: [
            section([CPListItem(text: "Selected \(selectedAbilities.count) of 2", detailText: selectedSummary, image: UIImage(systemName: "sparkles"))], header: "Your strengths"),
            section(abilityItems, header: "Choose abilities"),
            section([next], header: nil)
        ])
        interfaceController?.setRootTemplate(template, animated: true, completion: nil)
    }

    private func showName() {
        let items = suggestedNames.map { name in
            newItem(name, detail: "Use this suggested name.", icon: "person.fill") { [weak self] in
                self?.beginCampaign(named: name)
            }
        }
        let template = listTemplate(title: "3 of 3 · Name", sections: [
            section([CPListItem(text: "Suggested names", detailText: "Choose a name from the list to start.", image: UIImage(systemName: "wand.and.stars"))], header: "Your character"),
            section(items, header: "Names")
        ])
        interfaceController?.setRootTemplate(template, animated: true, completion: nil)
    }

    private func beginCampaign(named name: String) {
        let profile = CharacterCreationProfile(name: name, type: selectedType, abilities: selectedAbilities)
        session?.startNewCampaign(profile: profile, difficulty: .easy)
        showCampaignIntro()
    }

    private func showCampaignIntro() {
        guard let campaign = session?.campaign else { return }
        let description = "The Unwritten Realm is a rain-soaked frontier where old magic has gone quiet, but never truly disappeared. In Larkspur, a vanished duke left behind a map, a crescent-marked coin, and rumors of the Sunken Vault beneath the hill."
        let opening = campaign.recentTurns.first?.text ?? "Your story begins tonight."
        let start = newItem("Start", detail: "Begin the first chapter.", icon: "play.fill") { [weak self] in
            self?.showStory(readLatest: true)
        }
        let repeatReading = newItem("Repeat read aloud", detail: "Hear the campaign description and opening scene again.", icon: "speaker.wave.2.fill") { [weak self] in
            self?.speech.speak(text: "\(description) \(opening)", speakerName: "Dungeon Master")
        }
        let template = listTemplate(title: campaign.title, sections: [
            section([CPListItem(text: "Campaign", detailText: description, image: UIImage(systemName: "globe.americas.fill"))], header: "The setting"),
            section([CPListItem(text: "Opening scene", detailText: opening, image: UIImage(systemName: "text.bubble.fill"))], header: "Your story"),
            section([repeatReading, start], header: nil)
        ])
        speech.speak(text: description, speakerName: "Dungeon Master")
        interfaceController?.setRootTemplate(template, animated: true, completion: nil)
    }

    private func showStory(readLatest: Bool) {
        guard let campaign = session?.campaign else {
            showHome()
            return
        }
        screen = .story
        let location = campaign.currentLocation?.name ?? "Unknown location"
        let latest = campaign.recentTurns.last(where: { $0.speaker != .player })
        let dmItem = CPListItem(
            text: "Dungeon Master · \(location)",
            detailText: latest?.text ?? "The realm is waiting for your next choice.",
            image: UIImage(systemName: "moon.stars.fill")
        )
        dmItem.handler = { [weak self] _, completion in
            if let latest { self?.speech.speak(text: latest.text, speakerName: latest.speakerName ?? "Dungeon Master") }
            completion()
        }

        let items = [
            dmItem,
            newItem("Say what you’ll do", detail: "Speak a command for the Dungeon Master.", icon: "mic.fill") { [weak self] in
                self?.presentVoiceInput()
            },
            newItem("Inventory & Stats", detail: "Review health, abilities, items, and attributes.", icon: "backpack.fill") { [weak self] in
                self?.showInventoryAndStats()
            },
            newItem("Campaign Description", detail: "Hear the setting and story so far again.", icon: "text.book.closed") { [weak self] in
                self?.showCampaignIntro()
            },
            newItem("Return to Main Screen", detail: "Leave the story open for later.", icon: "house.fill") { [weak self] in
                self?.showHome()
            },
            newItem("Terminate Campaign", detail: "Delete this campaign and return to the main screen.", icon: "xmark.circle.fill") { [weak self] in
                self?.confirmTermination()
            }
        ]

        let template = listTemplate(title: "Chapter \(campaign.turnNumber + 1)", sections: [
            section([CPListItem(text: "Dungeon Master", detailText: session?.isProcessing == true ? "The Dungeon Master is thinking…" : "Your next move shapes the realm.", image: UIImage(systemName: session?.isProcessing == true ? "ellipsis.circle" : "sparkles"))], header: session?.isProcessing == true ? "Processing" : "Now playing"),
            section(items, header: "Actions")
        ])
        interfaceController?.setRootTemplate(template, animated: true, completion: nil)
        if readLatest, let latest { speech.speak(text: latest.text, speakerName: latest.speakerName ?? "Dungeon Master") }
    }

    private func showInventoryAndStats() {
        guard let player = session?.campaign?.player else { return }
        var stats = [
            CPListItem(text: player.name, detailText: "Level \(player.level) · HP \(player.hitPoints)/\(player.maxHitPoints)", image: UIImage(systemName: player.characterType.icon))
        ]
        for attribute in Attribute.allCases {
            let value = player.attributes[attribute, default: 0]
            let modifier = player.modifier(for: attribute)
            stats.append(CPListItem(text: attribute.rawValue.capitalized, detailText: "\(value)  (\(modifier >= 0 ? "+" : "")\(modifier))", image: UIImage(systemName: "chart.bar.fill")))
        }
        let inventory = player.inventory.map { item in
            CPListItem(text: item.name, detailText: item.description, image: UIImage(systemName: item.usable ? "cross.case.fill" : "shippingbox.fill"))
        }
        let back = newItem("Back to Campaign", detail: "Return to the Dungeon Master.", icon: "arrow.left") { [weak self] in
            self?.showStory(readLatest: false)
        }
        let template = listTemplate(title: "Inventory & Stats", sections: [
            section(stats, header: "Character"),
            section(inventory, header: "Inventory"),
            section([back], header: nil)
        ])
        interfaceController?.setRootTemplate(template, animated: true, completion: nil)
    }

    private func presentVoiceInput() {
        guard session?.isProcessing != true else { return }
        let states = [
            CPVoiceControlState(identifier: "listening", titleVariants: ["Listening…", "Tell the Dungeon Master what you’ll do"], image: UIImage(systemName: "mic.fill"), repeats: false),
            CPVoiceControlState(identifier: "processing", titleVariants: ["Processing…", "The Dungeon Master is thinking…"], image: UIImage(systemName: "ellipsis.circle"), repeats: true),
            CPVoiceControlState(identifier: "error", titleVariants: ["Try again"], image: UIImage(systemName: "exclamationmark.triangle.fill"), repeats: false)
        ]
        let template = CPVoiceControlTemplate(voiceControlStates: states)
        interfaceController?.presentTemplate(template, animated: true) { [weak self] success, _ in
            guard success else { return }
            self?.voiceInput.startRecording()
        }
    }

    private func submitVoiceCommand(_ text: String) {
        guard !text.isEmpty, let session, !session.isProcessing else { return }
        interfaceController?.dismissTemplate(animated: true, completion: nil)
        screen = .processing
        session.submit(text)
        showProcessing()
        waitForTurn()
    }

    private func showProcessing() {
        let item = CPListItem(text: "The Dungeon Master is thinking…", detailText: "Processing your action and dungeoning the next scene.", image: UIImage(systemName: "ellipsis.circle"))
        let template = listTemplate(title: "Chapter", sections: [section([item], header: "Please wait")])
        interfaceController?.setRootTemplate(template, animated: true, completion: nil)
    }

    private func waitForTurn() {
        Task { @MainActor [weak self] in
            while let self, self.session?.isProcessing == true {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard let self else { return }
            self.showStory(readLatest: true)
        }
    }

    private func confirmTermination() {
        let cancel = CPAlertAction(title: "Cancel", style: .cancel) { _ in }
        let terminate = CPAlertAction(title: "Terminate", style: .destructive) { [weak self] _ in
            self?.session?.deleteCampaign()
            self?.showHome()
        }
        let alert = CPAlertTemplate(titleVariants: ["Terminate this campaign?"], actions: [cancel, terminate])
        interfaceController?.presentTemplate(alert, animated: true, completion: nil)
    }

    private func listTemplate(title: String, sections: [CPListSection]) -> CPListTemplate {
        CPListTemplate(title: title, sections: sections)
    }

    private func section(_ items: [CPListItem], header: String?) -> CPListSection {
        CPListSection(items: items, header: header, sectionIndexTitle: nil)
    }

    private func newItem(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> CPListItem {
        let item = CPListItem(text: title, detailText: detail, image: UIImage(systemName: icon))
        item.handler = { _, completion in
            action()
            completion()
        }
        return item
    }
}
