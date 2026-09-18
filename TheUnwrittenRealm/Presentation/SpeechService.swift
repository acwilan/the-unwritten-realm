import AVFAudio
import SwiftUI

enum VoicePreference: String, CaseIterable, Identifiable {
    case deepMale
    case neutral
    case warmFemale

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepMale: return "Deep male"
        case .neutral: return "Neutral"
        case .warmFemale: return "Warm female"
        }
    }
}

@MainActor
final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var speakingEntryID: UUID?
    @Published var voicePreference: VoicePreference {
        didSet { UserDefaults.standard.set(voicePreference.rawValue, forKey: Self.voicePreferenceKey) }
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtteranceID: ObjectIdentifier?
    private static let voicePreferenceKey = "speech.voicePreference"

    override init() {
        let storedVoice = UserDefaults.standard.string(forKey: Self.voicePreferenceKey)
        voicePreference = VoicePreference(rawValue: storedVoice ?? "") ?? .deepMale
        super.init()
        synthesizer.delegate = self
    }

    func isSpeaking(_ entry: ConversationEntry) -> Bool {
        speakingEntryID == entry.id
    }

    func toggle(_ entry: ConversationEntry) {
        if isSpeaking(entry) {
            stop()
            return
        }

        stop()
        configureAudioSession()

        speak(text: entry.text, entryID: entry.id, speakerName: entry.speakerName)
    }

    func speak(text: String, entryID: UUID? = nil, speakerName: String? = nil) {
        stop()
        configureAudioSession()

        let profile = VoiceCatalog.profile(for: speakerName, preference: voicePreference)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = VoiceCatalog.voice(for: profile)
        utterance.rate = profile.rate
        utterance.pitchMultiplier = profile.pitch
        utterance.volume = 1.0

        activeUtteranceID = ObjectIdentifier(utterance)
        speakingEntryID = entryID
        synthesizer.speak(utterance)
    }

    func toggle(text: String, entryID: UUID? = nil, speakerName: String? = nil) {
        if entryID != nil, speakingEntryID == entryID {
            stop()
        } else {
            speak(text: text, entryID: entryID, speakerName: speakerName)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        activeUtteranceID = nil
        speakingEntryID = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.activeUtteranceID == utteranceID else { return }
            self.finishSpeaking()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.activeUtteranceID == utteranceID else { return }
            self.finishSpeaking()
        }
    }

    private func finishSpeaking() {
        activeUtteranceID = nil
        speakingEntryID = nil
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? audioSession.setActive(true)
    }
}

private struct VoiceProfile {
    let preferredNames: [String]
    let pitch: Float
    let rate: Float
}

private enum VoiceCatalog {
    static func profile(for speakerName: String?, preference: VoicePreference) -> VoiceProfile {
        switch preference {
        case .deepMale:
            return VoiceProfile(preferredNames: ["Daniel", "Aaron", "Alex", "Oliver"], pitch: 0.78, rate: 0.44)
        case .warmFemale:
            return VoiceProfile(preferredNames: ["Samantha", "Ava", "Karen", "Moira"], pitch: 1.02, rate: 0.46)
        case .neutral:
            break
        }

        let name = speakerName?.lowercased() ?? ""
        if name.contains("mira") {
            return VoiceProfile(preferredNames: ["Samantha", "Ava", "Karen"], pitch: 1.08, rate: 0.48)
        }
        if name.contains("brom") {
            return VoiceProfile(preferredNames: ["Daniel", "Alex", "Aaron"], pitch: 0.88, rate: 0.44)
        }
        if name.contains("elian") {
            return VoiceProfile(preferredNames: ["Daniel", "Oliver", "Tom"], pitch: 0.96, rate: 0.46)
        }
        if name.contains("nessa") {
            return VoiceProfile(preferredNames: ["Karen", "Moira", "Samantha"], pitch: 0.92, rate: 0.46)
        }
        if name.contains("vek") {
            return VoiceProfile(preferredNames: ["Samantha", "Ava", "Daniel"], pitch: 1.16, rate: 0.54)
        }
        return VoiceProfile(preferredNames: ["Alex", "Samantha", "Daniel"], pitch: 1.0, rate: 0.46)
    }

    static func voice(for profile: VoiceProfile) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }

        for preferredName in profile.preferredNames {
            if let voice = voices.first(where: { $0.name.caseInsensitiveCompare(preferredName) == .orderedSame }) {
                return voice
            }
        }

        return AVSpeechSynthesisVoice(language: "en-US") ?? voices.first
    }
}
