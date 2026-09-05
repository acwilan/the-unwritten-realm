import AVFAudio
import SwiftUI

@MainActor
final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var speakingEntryID: UUID?

    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtteranceID: ObjectIdentifier?

    override init() {
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

        let profile = VoiceCatalog.profile(for: entry.speakerName)
        let utterance = AVSpeechUtterance(string: entry.text)
        utterance.voice = VoiceCatalog.voice(for: profile)
        utterance.rate = profile.rate
        utterance.pitchMultiplier = profile.pitch
        utterance.volume = 1.0

        activeUtteranceID = ObjectIdentifier(utterance)
        speakingEntryID = entry.id
        synthesizer.speak(utterance)
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
    static func profile(for speakerName: String?) -> VoiceProfile {
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
