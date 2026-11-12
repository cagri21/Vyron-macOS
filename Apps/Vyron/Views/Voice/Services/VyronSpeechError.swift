import Foundation

enum VyronSpeechError: LocalizedError {
    case permissionConfiguration
    case microphonePermission
    case speechPermission
    case recognitionUnavailable
    case onDeviceUnavailable
    case microphoneUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionConfiguration: VyronVoiceText.permissionConfiguration
        case .microphonePermission: VyronVoiceText.microphonePermission
        case .speechPermission: VyronVoiceText.speechPermission
        case .recognitionUnavailable: VyronVoiceText.recognitionUnavailable
        case .onDeviceUnavailable: VyronVoiceText.onDeviceUnavailable
        case .microphoneUnavailable: VyronVoiceText.microphoneUnavailable
        }
    }
}
