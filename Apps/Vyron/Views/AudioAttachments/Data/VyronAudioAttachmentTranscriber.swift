import Foundation
import Speech

@MainActor
enum VyronAudioAttachmentTranscriber {
    static func transcribe(_ url: URL) async -> String? {
        guard Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") is String,
            let recognizer = SFSpeechRecognizer(),
            recognizer.supportsOnDeviceRecognition,
            recognizer.isAvailable,
            await hasSpeechPermission(),
            !Task.isCancelled
        else { return nil }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        let (results, continuation) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let recognition = recognizer.recognitionTask(with: request) { @Sendable result, error in
            if let result, result.isFinal {
                continuation.yield(result.bestTranscription.formattedString)
                continuation.finish()
            } else if error != nil {
                continuation.finish()
            }
        }
        let expiration = Task {
            do {
                try await Task.sleep(for: VyronAudioAttachmentLimits.transcriptionTimeout)
                continuation.finish()
            } catch is CancellationError {
                return
            }
        }
        defer {
            expiration.cancel()
            recognition.cancel()
        }
        var result = results.makeAsyncIterator()
        return await result.next()
    }

    private static func hasSpeechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            let (results, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.yield(status == .authorized)
                continuation.finish()
            }
            var result = results.makeAsyncIterator()
            return await result.next() == true
        case .restricted, .denied:
            return false
        @unknown default:
            return false
        }
    }
}
