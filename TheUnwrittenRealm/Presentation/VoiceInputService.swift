import AVFAudio
import Speech
import SwiftUI

/// A small, single-turn speech recognizer used by the hands-free campaign flow.
@MainActor
final class VoiceInputService: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published private(set) var finalTranscript: String?
    @Published var errorMessage: String?
    var onFinalTranscript: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    override init() {
        super.init()
        recognizer?.delegate = self
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        finalTranscript = nil
        transcript = ""
        errorMessage = nil

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.errorMessage = "Speech recognition permission is required for voice actions."
                    return
                }
                AVAudioApplication.requestRecordPermission { [weak self] granted in
                    Task { @MainActor in
                        guard let self else { return }
                        guard granted else {
                            self.errorMessage = "Microphone permission is required for voice actions."
                            return
                        }
                        self.beginRecognition()
                    }
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        isRecording = false
    }

    func cancel() {
        recognitionTask?.cancel()
        recognitionTask = nil
        stopRecording()
        request = nil
        transcript = ""
        finalTranscript = nil
    }

    func clearFinalTranscript() {
        finalTranscript = nil
    }

    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        guard !available else { return }
        Task { @MainActor [weak self] in
            self?.errorMessage = "Speech recognition is temporarily unavailable."
            self?.cancel()
        }
    }

    private func beginRecognition() {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is temporarily unavailable."
            return
        }

        recognitionTask?.cancel()
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request else { return }
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            errorMessage = "Could not start the microphone."
            cancel()
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finishRecognition(with: self.transcript)
                    }
                }
                if error != nil {
                    if self.transcript.isEmpty {
                        self.errorMessage = "I couldn't hear that. Try again."
                    } else {
                        self.finishRecognition(with: self.transcript)
                    }
                }
            }
        }
    }

    private func finishRecognition(with text: String) {
        stopRecording()
        recognitionTask = nil
        request = nil
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        finalTranscript = cleaned.isEmpty ? nil : cleaned
        if !cleaned.isEmpty { onFinalTranscript?(cleaned) }
    }
}
