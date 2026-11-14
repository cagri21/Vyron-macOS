import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation
import Speech
import VyronAutomation

struct VyronPermissionsSystemAccess: Sendable {
    let status: @MainActor (VyronMacPrivacyPane) -> VyronPermissionStatus
    let request: @MainActor (VyronMacPrivacyPane) async -> Void
    let openSettings: @MainActor (VyronMacPrivacyPane) -> Bool

    static let system = Self(status: readStatus, request: requestAccess, openSettings: { $0.openSettings() })

    @MainActor
    private static func readStatus(_ pane: VyronMacPrivacyPane) -> VyronPermissionStatus {
        switch pane {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notGranted
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        case .microphone:
            guard VyronPermissionUsageDescription.microphone.isPresent else { return .unavailable }
            return microphoneStatus()
        case .speechRecognition:
            guard VyronPermissionUsageDescription.speechRecognition.isPresent else { return .unavailable }
            return speechRecognitionStatus()
        }
    }

    @MainActor
    private static func requestAccess(_ pane: VyronMacPrivacyPane) async {
        guard !Task.isCancelled, readStatus(pane) == .notRequested else { return }
        switch pane {
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .speechRecognition:
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                SFSpeechRecognizer.requestAuthorization { @Sendable _ in continuation.resume() }
            }
        case .accessibility, .screenRecording:
            break
        }
    }

    @MainActor
    private static func microphoneStatus() -> VyronPermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .denied: .notGranted
        case .notDetermined: .notRequested
        case .restricted: .restricted
        @unknown default: .unavailable
        }
    }

    @MainActor
    private static func speechRecognitionStatus() -> VyronPermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .granted
        case .denied: .notGranted
        case .notDetermined: .notRequested
        case .restricted: .restricted
        @unknown default: .unavailable
        }
    }
}
