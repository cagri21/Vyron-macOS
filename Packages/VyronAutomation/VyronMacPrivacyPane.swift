import AppKit

public enum VyronMacPrivacyPane: String, CaseIterable, Sendable {
    case accessibility = "Privacy_Accessibility"
    case screenRecording = "Privacy_ScreenCapture"
    case microphone = "Privacy_Microphone"
    case speechRecognition = "Privacy_SpeechRecognition"

    public var settingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)")
    }

    @MainActor @discardableResult
    public func openSettings() -> Bool {
        guard let settingsURL else { return false }
        return NSWorkspace.shared.open(settingsURL)
    }
}
