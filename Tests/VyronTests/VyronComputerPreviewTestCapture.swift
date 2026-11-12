import Foundation
import VyronAutomation
@testable import Vyron

@MainActor
final class VyronComputerPreviewTestCapture: VyronComputerPreviewCapturing {
    private(set) var requests: [VyronComputerPreviewTestRequest] = []

    func capturePreview(application: DesktopApplication) async throws -> VyronMacControlPreview {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(.init(application: application, completion: continuation))
        }
    }
}
