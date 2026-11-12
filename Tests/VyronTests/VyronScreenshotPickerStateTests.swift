import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronScreenshotPickerStateTests: XCTestCase {
    func testPermissionIsRequestedOnlyByExplicitActionAndSuccessfulRetryNeedsSelection() async throws {
        let capture = VyronScreenshotPickerTestCapture()
        let state = VyronScreenshotPickerState(captureService: capture)
        state.start()
        XCTAssertTrue(state.isLoading)
        try await waitUntil { capture.sourceRequests.count == 1 }
        capture.sourceRequests[0].resume(throwing: VyronScreenshotCaptureError.permissionRequired)
        try await waitUntil { !state.isLoading }
        XCTAssertTrue(state.needsPermission)
        XCTAssertNotNil(state.errorMessage)
        XCTAssertEqual(capture.permissionRequests, 0)
        XCTAssertEqual(capture.settingsRequests, 0)
        XCTAssertFalse(state.canCapture)

        capture.permissionGranted = true
        state.requestPermission()
        XCTAssertEqual(capture.permissionRequests, 1)
        try await waitUntil { capture.sourceRequests.count == 2 }
        let window = source(1)
        capture.sourceRequests[1].resume(returning: [window])
        try await waitUntil { !state.isLoading }
        XCTAssertFalse(state.needsPermission)
        XCTAssertNil(state.errorMessage)
        XCTAssertFalse(state.canCapture)
        state.selectedSourceID = window.id
        XCTAssertTrue(state.canCapture)
        state.stop()
    }

    func testRefreshDiscardsLatePreviousSourceListing() async throws {
        let capture = VyronScreenshotPickerTestCapture()
        let state = VyronScreenshotPickerState(captureService: capture)
        state.start()
        try await waitUntil { capture.sourceRequests.count == 1 }
        state.refresh()
        try await waitUntil { capture.sourceRequests.count == 2 }
        let current = source(2)
        capture.sourceRequests[1].resume(returning: [current])
        try await waitUntil { !state.isLoading }
        state.selectedSourceID = current.id
        capture.sourceRequests[0].resume(returning: [source(1)])
        try await waitUntil { capture.finishedListings == 2 }
        await Task.yield()
        XCTAssertEqual(state.sources, [current])
        XCTAssertEqual(state.selectedSourceID, current.id)
        XCTAssertTrue(state.canCapture)
        state.stop()
    }

    func testCloseDiscardsNonCooperativeLateCapture() async throws {
        let capture = VyronScreenshotPickerTestCapture()
        let state = try await preparedState(capture)
        var delivered: [Data] = []
        state.captureSelection { data, _ in delivered.append(data) }
        try await waitUntil { capture.captureRequests.count == 1 }
        XCTAssertTrue(state.isCapturing)
        XCTAssertFalse(state.canCapture)
        state.stop()
        capture.captureRequests[0].resume(returning: Data([1, 2, 3]))
        try await waitUntil { capture.finishedCaptures == 1 }
        await Task.yield()
        XCTAssertTrue(delivered.isEmpty)
        XCTAssertFalse(state.isCapturing)
        XCTAssertFalse(state.canCapture)
    }

    func testChangedSelectionDiscardsLateCapture() async throws {
        let capture = VyronScreenshotPickerTestCapture()
        let state = try await preparedState(capture)
        var delivered = false
        state.captureSelection { _, _ in delivered = true }
        try await waitUntil { capture.captureRequests.count == 1 }
        state.selectedSourceID = nil
        capture.captureRequests[0].resume(returning: Data([1]))
        try await waitUntil { !state.isCapturing }
        XCTAssertFalse(delivered)
        state.stop()
    }

    func testMissingSourceClearsSelectionAndRefreshAllowsSuccessfulCapture() async throws {
        let capture = VyronScreenshotPickerTestCapture()
        let state = try await preparedState(capture)
        var delivered: Data?
        var deliveredName: String?
        state.captureSelection { data, name in
            delivered = data
            deliveredName = name
        }
        try await waitUntil { capture.captureRequests.count == 1 }
        capture.captureRequests[0].resume(throwing: VyronScreenshotCaptureError.sourceUnavailable)
        try await waitUntil { !state.isCapturing }
        XCTAssertNil(state.selectedSourceID)
        XCTAssertNotNil(state.errorMessage)
        XCTAssertFalse(state.canCapture)

        state.refresh()
        try await waitUntil { capture.sourceRequests.count == 2 }
        let replacement = source(2)
        capture.sourceRequests[1].resume(returning: [replacement])
        try await waitUntil { !state.isLoading }
        XCTAssertNil(state.errorMessage)
        state.selectedSourceID = replacement.id
        state.captureSelection { data, name in
            delivered = data
            deliveredName = name
        }
        try await waitUntil { capture.captureRequests.count == 2 }
        let data = Data([2, 3, 4])
        capture.captureRequests[1].resume(returning: data)
        try await waitUntil { !state.isCapturing }
        XCTAssertEqual(delivered, data)
        XCTAssertEqual(deliveredName, replacement.name)
        XCTAssertEqual(capture.capturedSourceIDs, [source(1).id, replacement.id])
        state.stop()
    }

    func testRevokedPermissionBlocksCaptureUntilRefreshSucceeds() async throws {
        let capture = VyronScreenshotPickerTestCapture()
        let state = try await preparedState(capture)
        state.captureSelection { _, _ in XCTFail("Permission failure must not deliver an image.") }
        try await waitUntil { capture.captureRequests.count == 1 }
        capture.captureRequests[0].resume(throwing: VyronScreenshotCaptureError.permissionRequired)
        try await waitUntil { !state.isCapturing }
        XCTAssertTrue(state.needsPermission)
        XCTAssertFalse(state.canCapture)
        state.refresh()
        try await waitUntil { capture.sourceRequests.count == 2 }
        capture.sourceRequests[1].resume(returning: [source(1)])
        try await waitUntil { !state.isLoading }
        XCTAssertFalse(state.needsPermission)
        XCTAssertTrue(state.canCapture)
        XCTAssertEqual(capture.permissionRequests, 0)
        state.stop()
    }

    func testUnknownListingFailureClearsLoadingAndCanRetry() async throws {
        let capture = VyronScreenshotPickerTestCapture()
        let state = VyronScreenshotPickerState(captureService: capture)
        state.start()
        try await waitUntil { capture.sourceRequests.count == 1 }
        capture.sourceRequests[0].resume(throwing: CocoaError(.fileReadUnknown))
        try await waitUntil { !state.isLoading }
        XCTAssertNotNil(state.errorMessage)
        XCTAssertFalse(state.needsPermission)
        state.refresh()
        try await waitUntil { capture.sourceRequests.count == 2 }
        capture.sourceRequests[1].resume(returning: [])
        try await waitUntil { !state.isLoading }
        XCTAssertNil(state.errorMessage)
        XCTAssertTrue(state.sources.isEmpty)
        state.stop()
    }

    private func preparedState(_ capture: VyronScreenshotPickerTestCapture) async throws -> VyronScreenshotPickerState {
        let state = VyronScreenshotPickerState(captureService: capture)
        state.start()
        try await waitUntil { capture.sourceRequests.count == 1 }
        let window = source(1)
        capture.sourceRequests[0].resume(returning: [window])
        try await waitUntil { !state.isLoading }
        state.selectedSourceID = window.id
        return state
    }

    private func source(_ identifier: UInt32) -> VyronScreenshotSource {
        VyronScreenshotSource(
            id: "window-\(identifier)",
            name: "Simulator \(identifier)",
            target: .window(VyronScreenshotWindowTarget(
                windowID: identifier,
                processID: 42,
                bundleIdentifier: "test.simulator"
            ))
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<1_000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The in-memory screenshot operation did not finish.")
        throw CancellationError()
    }
}
