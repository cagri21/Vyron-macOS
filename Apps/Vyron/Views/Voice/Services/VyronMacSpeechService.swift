import AVFoundation
import Foundation
import Speech
import os

@MainActor
final class VyronMacSpeechService: NSObject, VyronSpeechService, AVSpeechSynthesizerDelegate {
    private var engine: AVAudioEngine?
    private var synthesizer: AVSpeechSynthesizer?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var listeningID: UUID?
    private var hasInputTap = false
    private var utteranceID: ObjectIdentifier?
    private var speechCompletion: (@MainActor () -> Void)?

    // Apple's recognition request is intentionally fed from the audio render callback.
    // The lock serializes append/endAudio and never exposes this reference across tasks.
    private let audioRequest = OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>(uncheckedState: nil)

    var voices: [VyronVoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { !$0.voiceTraits.contains(.isPersonalVoice) }
            .map { VyronVoiceOption(id: $0.identifier, name: $0.name, language: $0.language) }
            .sorted {
                if $0.language == $1.language { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return $0.language < $1.language
            }
    }

    func startListening(
        onUpdate: @escaping @MainActor (String, Bool) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) async throws {
        stopListening()
        stopSpeaking()
        let id = UUID()
        listeningID = id
        do {
            try await requestPermissions(generationID: id)
            try Task.checkCancellation()
            guard listeningID == id else { throw CancellationError() }
            guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
                throw VyronSpeechError.recognitionUnavailable
            }
            guard recognizer.supportsOnDeviceRecognition else { throw VyronSpeechError.onDeviceUnavailable }
            self.recognizer = recognizer
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            request.addsPunctuation = true
            audioRequest.withLockUnchecked { $0 = request }

            let engine = AVAudioEngine()
            self.engine = engine
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw VyronSpeechError.microphoneUnavailable
            }
            let sink = audioRequest
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { @Sendable buffer, _ in
                sink.withLockUnchecked { $0?.append(buffer) }
            }
            hasInputTap = true
            recognitionTask = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let failed = error != nil
                Task { @MainActor [weak self] in
                    guard let self, self.listeningID == id else { return }
                    if isFinal {
                        self.stopListening()
                        onUpdate(text ?? "", true)
                    } else if failed {
                        self.stopListening()
                        onFailure(VyronVoiceText.recognitionFailed)
                    } else if let text {
                        onUpdate(text, false)
                    }
                }
            }
            engine.prepare()
            try engine.start()
        } catch {
            if listeningID == id { stopListening() }
            throw error
        }
    }

    func stopListening() {
        listeningID = nil
        engine?.stop()
        if hasInputTap, let engine {
            engine.inputNode.removeTap(onBus: 0)
        }
        hasInputTap = false
        audioRequest.withLock {
            $0?.endAudio()
            $0 = nil
        }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizer = nil
        engine?.reset()
        engine = nil
    }

    func speak(_ text: String, voiceID: String, onFinished: @escaping @MainActor () -> Void) {
        stopListening()
        stopSpeaking()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onFinished()
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceID) ?? AVSpeechSynthesisVoice(language: nil)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utteranceID = ObjectIdentifier(utterance)
        speechCompletion = onFinished
        let synthesizer = self.synthesizer ?? AVSpeechSynthesizer()
        synthesizer.delegate = self
        self.synthesizer = synthesizer
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        utteranceID = nil
        speechCompletion = nil
        synthesizer?.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completeSpeech(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        completeSpeech(ObjectIdentifier(utterance))
    }

    private nonisolated func completeSpeech(_ id: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, self.utteranceID == id else { return }
            self.utteranceID = nil
            let completion = self.speechCompletion
            self.speechCompletion = nil
            completion?()
        }
    }

    private func requestPermissions(generationID: UUID) async throws {
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String != nil,
            Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") as? String != nil
        else { throw VyronSpeechError.permissionConfiguration }
        let microphoneAllowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphoneAllowed = true
        case .notDetermined: microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        default: microphoneAllowed = false
        }
        guard microphoneAllowed else { throw VyronSpeechError.microphonePermission }
        try Task.checkCancellation()
        guard listeningID == generationID else { throw CancellationError() }
        let speechStatus: SFSpeechRecognizerAuthorizationStatus
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            speechStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        } else {
            speechStatus = SFSpeechRecognizer.authorizationStatus()
        }
        guard speechStatus == .authorized else { throw VyronSpeechError.speechPermission }
    }
}
