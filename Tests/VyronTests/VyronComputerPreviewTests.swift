import Foundation
import XCTest
import VyronAutomation
@testable import Vyron

@MainActor
final class VyronComputerPreviewTests: XCTestCase {
    func testPreviewDoesNotCaptureWithoutScreenPermission() {
        let capture = VyronComputerPreviewTestCapture()
        let model = AutomationModel(previewCapture: capture)
        model.applications = [app("first")]
        model.selectedApplicationID = "first"
        XCTAssertNil(model.controlPreviewTask)
        XCTAssertTrue(capture.requests.isEmpty)
    }

    func testSwitchingAppsDiscardsLateCaptureFromPreviousApp() async throws {
        let capture = VyronComputerPreviewTestCapture()
        let model = preparedModel(capture)
        let first = app("first")
        let second = app("second")
        model.applications = [first, second]
        model.selectedApplicationID = first.id
        try await waitUntil { capture.requests.count == 1 }
        let previousTask = model.controlPreviewTask
        model.selectedApplicationID = second.id
        try await waitUntil { capture.requests.count == 2 }
        capture.requests[1].completion.resume(returning: preview(second))
        try await waitUntil { model.controlPreview?.applicationID == second.id }
        capture.requests[0].completion.resume(returning: preview(first))
        await previousTask?.value
        XCTAssertEqual(model.controlPreview?.applicationID, second.id)
        model.stopControlPreview()
    }

    func testCloseCancelsCaptureAndDiscardsNonCooperativeLateResult() async throws {
        let capture = VyronComputerPreviewTestCapture()
        let model = preparedModel(capture)
        let target = app("first")
        model.applications = [target]
        model.selectedApplicationID = target.id
        try await waitUntil { capture.requests.count == 1 }
        let task = model.controlPreviewTask
        model.close()
        XCTAssertTrue(task?.isCancelled == true)
        XCTAssertNil(model.controlPreviewGeneration)
        capture.requests[0].completion.resume(returning: preview(target))
        await task?.value
        XCTAssertNil(model.controlPreview)
    }

    func testMissingWindowShowsErrorThenRetriesAndClearsErrorOnSuccess() async throws {
        let capture = VyronComputerPreviewTestCapture()
        let model = preparedModel(capture)
        let target = app("first")
        model.applications = [target]
        model.selectedApplicationID = target.id
        try await waitUntil { capture.requests.count == 1 }
        capture.requests[0].completion.resume(throwing: VyronMacPreviewError.windowUnavailable)
        try await waitUntil { model.controlPreviewMessage != nil }
        XCTAssertNil(model.controlPreview)
        try await waitUntil { capture.requests.count == 2 }
        capture.requests[1].completion.resume(returning: preview(target))
        try await waitUntil { model.controlPreview != nil }
        XCTAssertNil(model.controlPreviewMessage)
        model.stopControlPreview()
    }

    func testRevokedScreenPermissionStopsCapturing() async throws {
        let capture = VyronComputerPreviewTestCapture()
        let model = preparedModel(capture)
        model.applications = [app("first")]
        model.selectedApplicationID = "first"
        try await waitUntil { capture.requests.count == 1 }
        let task = model.controlPreviewTask
        capture.requests[0].completion.resume(throwing: VyronMacPreviewError.permissionRequired)
        await task?.value
        XCTAssertFalse(model.screenCaptureGranted)
        XCTAssertNil(model.controlPreview)
        XCTAssertNotNil(model.controlPreviewMessage)
        XCTAssertNil(model.controlPreviewGeneration)
        XCTAssertNil(model.controlPreviewTask)
        model.stopControlPreview()
    }

    private func preparedModel(_ capture: VyronComputerPreviewTestCapture) -> AutomationModel {
        let model = AutomationModel(previewCapture: capture)
        model.screenCaptureGranted = true
        return model
    }

    private func app(_ id: String) -> DesktopApplication {
        DesktopApplication(id: id, name: id, bundleIdentifier: id, processIdentifier: 1)
    }

    private func preview(_ app: DesktopApplication) -> VyronMacControlPreview {
        VyronMacControlPreview(
            applicationID: app.id,
            capturedAt: Date(),
            screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            imageData: Data()
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The in-memory preview operation did not finish.")
        throw CancellationError()
    }
}
