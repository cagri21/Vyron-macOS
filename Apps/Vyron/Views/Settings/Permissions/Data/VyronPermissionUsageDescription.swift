import Foundation

enum VyronPermissionUsageDescription: String {
    case microphone = "NSMicrophoneUsageDescription"
    case speechRecognition = "NSSpeechRecognitionUsageDescription"

    var isPresent: Bool {
        guard let description = Bundle.main.object(forInfoDictionaryKey: rawValue) as? String else { return false }
        return !description.isEmpty
    }
}
