import Foundation
import XCTest
@testable import Vyron
import VyronCore

@MainActor
final class VyronMacWorkScreenshotTests: XCTestCase {
    func testListsOnlyRequestedApplicationWindowsAndNeverDisplays() async throws {
        let test = VyronMacWorkScreenshotTestHarness()
        let result = try await test.list([
            window(1),
            window(2, applicationID: "com.apple.Safari"),
            VyronScreenshotSource(
                id: "display-1", name: "Display",
                target: .display(VyronScreenshotDisplayTarget(displayID: 1))
            )
        ])
        let windows = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.text.utf8)) as? [[String: Any]]
        )
        XCTAssertFalse(result.isError)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0]["source_id"] as? String, "window-1")
        XCTAssertEqual(windows[0]["application_id"] as? String, "com.apple.iphonesimulator")
        XCTAssertEqual(windows[0]["process_id"] as? Int, 42)
        XCTAssertTrue(result.images.isEmpty)
        XCTAssertTrue(test.state.capturedImages.isEmpty)
    }

    func testSuccessfulCaptureNormalizesPixelsAndPublishesVisibleArtifactOnce() async throws {
        let test = VyronMacWorkScreenshotTestHarness()
        _ = try await test.list([window(1)])
        let task = Task { try await test.tools.execute(captureCall("window-1")) }
        try await test.waitUntil { test.capture.captureRequests.count == 1 }
        test.capture.captureRequests[0].resume(returning: try VyronScreenshotTestImage.jpeg())
        let result = try await task.value

        XCTAssertFalse(result.isError)
        let image = try XCTUnwrap(result.images.first)
        XCTAssertEqual(image.mimeType, "image/png")
        XCTAssertTrue(image.data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(test.state.capturedImages, [image])
        XCTAssertEqual(test.capture.capturedSourceIDs, ["window-1"])

        let repeated = try await test.tools.execute(captureCall("window-1"))
        XCTAssertTrue(repeated.isError)
        XCTAssertTrue(repeated.images.isEmpty)
        XCTAssertEqual(test.capture.captureRequests.count, 1)
    }

    func testCaptureRequiresCurrentSourceFromLatestAppListing() async throws {
        let test = VyronMacWorkScreenshotTestHarness()
        let unlisted = try await test.tools.execute(captureCall("window-1"))
        XCTAssertTrue(unlisted.isError)
        _ = try await test.list([window(1)])
        _ = try await test.list([window(2, applicationID: "com.apple.Safari")], applicationID: "com.apple.Safari")

        let stale = try await test.tools.execute(captureCall("window-1"))
        XCTAssertTrue(stale.isError)
        XCTAssertTrue(stale.images.isEmpty)
        XCTAssertTrue(test.capture.capturedSourceIDs.isEmpty)
    }

    func testArtifactPublicationFailureDoesNotReturnPixelsAsASuccess() async throws {
        let test = VyronMacWorkScreenshotTestHarness()
        test.state.failPublication = true
        _ = try await test.list([window(1)])
        let task = Task { try await test.tools.execute(captureCall("window-1")) }
        try await test.waitUntil { test.capture.captureRequests.count == 1 }
        test.capture.captureRequests[0].resume(returning: try VyronScreenshotTestImage.jpeg())
        let result = try await task.value

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.images.isEmpty)
        XCTAssertTrue(test.state.capturedImages.isEmpty)
    }

    func testProjectChangeInvalidationRejectsPreviouslyListedSourceBeforeCapture() async throws {
        let test = VyronMacWorkScreenshotTestHarness()
        _ = try await test.list([window(1)])
        test.tools.invalidateSources()
        let result = try await test.tools.execute(captureCall("window-1"))

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.images.isEmpty)
        XCTAssertTrue(test.capture.captureRequests.isEmpty)
        XCTAssertTrue(test.state.capturedImages.isEmpty)
    }

    func testScreenPermissionIsRequestedOnceThenSourceListingIsRetried() async throws {
        let test = VyronMacWorkScreenshotTestHarness()
        test.capture.permissionGranted = true
        let first = Task { try await test.tools.execute(listCall()) }
        try await test.waitUntil { test.capture.sourceRequests.count == 1 }
        test.capture.sourceRequests[0].resume(throwing: VyronScreenshotCaptureError.permissionRequired)
        try await test.waitUntil { test.capture.sourceRequests.count == 2 }
        test.capture.sourceRequests[1].resume(returning: [window(1)])
        let permitted = try await first.value
        XCTAssertFalse(permitted.isError)
        XCTAssertEqual(test.capture.permissionRequests, 1)

        let second = Task { try await test.tools.execute(listCall()) }
        try await test.waitUntil { test.capture.sourceRequests.count == 3 }
        test.capture.sourceRequests[2].resume(throwing: VyronScreenshotCaptureError.permissionRequired)
        let denied = try await second.value
        XCTAssertTrue(denied.isError)
        XCTAssertTrue(denied.images.isEmpty)
        XCTAssertEqual(test.capture.permissionRequests, 1)
        XCTAssertEqual(test.capture.sourceRequests.count, 3)
    }

    func testPermissionDenialDoesNotCaptureOrRepeatedlyPrompt() async throws {
        let test = VyronMacWorkScreenshotTestHarness()
        let task = Task { try await test.tools.execute(listCall()) }
        try await test.waitUntil { test.capture.sourceRequests.count == 1 }
        test.capture.sourceRequests[0].resume(throwing: VyronScreenshotCaptureError.permissionRequired)
        let result = try await task.value

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("Screen Recording permission is required"))
        XCTAssertTrue(result.images.isEmpty)
        XCTAssertEqual(test.capture.permissionRequests, 1)
        XCTAssertTrue(test.capture.captureRequests.isEmpty)
        XCTAssertTrue(test.state.capturedImages.isEmpty)
    }

    func testRevokedPermissionDuringCaptureDoesNotDeliverPixelsOrArtifact() async throws {
        let test = VyronMacWorkScreenshotTestHarness()
        _ = try await test.list([window(1)])
        let task = Task { try await test.tools.execute(captureCall("window-1")) }
        try await test.waitUntil { test.capture.captureRequests.count == 1 }
        test.capture.captureRequests[0].resume(throwing: VyronScreenshotCaptureError.permissionRequired)
        let result = try await task.value

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.images.isEmpty)
        XCTAssertTrue(test.state.capturedImages.isEmpty)
        XCTAssertEqual(test.capture.permissionRequests, 0)
    }

    func testLateSourceListingCannotBecomeAvailableToAnotherResponse() async throws {
        let test = VyronMacWorkScreenshotTestHarness()
        let task = Task { try await test.tools.execute(listCall()) }
        try await test.waitUntil { test.capture.sourceRequests.count == 1 }
        test.state.isCurrent = false
        test.capture.sourceRequests[0].resume(returning: [window(1)])
        do {
            _ = try await task.value
            XCTFail("A stale response must not receive app-window sources.")
        } catch is CancellationError {}
        XCTAssertTrue(test.capture.captureRequests.isEmpty)
        XCTAssertTrue(test.state.capturedImages.isEmpty)
    }

    func testLateCaptureCannotPublishPixelsOrArtifactAfterResponseChanges() async throws {
        let test = VyronMacWorkScreenshotTestHarness()
        _ = try await test.list([window(1)])
        let task = Task { try await test.tools.execute(captureCall("window-1")) }
        try await test.waitUntil { test.capture.captureRequests.count == 1 }
        test.state.isCurrent = false
        test.capture.captureRequests[0].resume(returning: try VyronScreenshotTestImage.jpeg())
        do {
            _ = try await task.value
            XCTFail("A stale capture must not publish screenshot evidence.")
        } catch is CancellationError {}
        XCTAssertTrue(test.state.capturedImages.isEmpty)
    }

    func testStoppedCaptureDiscardsNonCooperativeLatePixels() async throws {
        let test = VyronMacWorkScreenshotTestHarness()
        _ = try await test.list([window(1)])
        let task = Task { try await test.tools.execute(captureCall("window-1")) }
        try await test.waitUntil { test.capture.captureRequests.count == 1 }
        task.cancel()
        test.capture.captureRequests[0].resume(returning: try VyronScreenshotTestImage.jpeg())
        do {
            _ = try await task.value
            XCTFail("A stopped capture must not publish screenshot evidence.")
        } catch is CancellationError {}
        XCTAssertTrue(test.state.capturedImages.isEmpty)
    }

    func testConcurrentOperationsAndUnlistedTargetsDoNotStartAnotherCapture() async throws {
        let test = VyronMacWorkScreenshotTestHarness()
        _ = try await test.list([window(1)])
        let task = Task { try await test.tools.execute(captureCall("window-1")) }
        try await test.waitUntil { test.capture.captureRequests.count == 1 }
        let concurrent = try await test.tools.execute(listCall())
        XCTAssertTrue(concurrent.isError)
        XCTAssertEqual(test.capture.sourceRequests.count, 1)
        test.capture.captureRequests[0].resume(returning: try VyronScreenshotTestImage.jpeg())
        let captured = try await task.value
        XCTAssertFalse(captured.isError)

        let guessed = try await test.tools.execute(captureCall("display-1"))
        XCTAssertTrue(guessed.isError)
        XCTAssertEqual(test.capture.captureRequests.count, 1)
    }

    func testUnexpectedArgumentsAndInvalidApplicationIDsFailBeforeNativeRead() async throws {
        let test = VyronMacWorkScreenshotTestHarness()
        for call in [
            DevelopmentToolCall(name: "vyron_mac_windows", arguments: ["application_id": .string("../Secrets")]),
            DevelopmentToolCall(name: "vyron_mac_windows", arguments: [
                "application_id": .string("com.apple.Safari"), "display": .bool(true)
            ]),
            DevelopmentToolCall(name: "vyron_mac_screenshot", arguments: ["source_id": .number(1)])
        ] {
            let result = try await test.tools.execute(call)
            XCTAssertTrue(result.isError)
            XCTAssertTrue(result.images.isEmpty)
        }
        XCTAssertTrue(test.capture.sourceRequests.isEmpty)
        XCTAssertTrue(test.capture.captureRequests.isEmpty)
    }

    private func window(_ identifier: UInt32, applicationID: String = "com.apple.iphonesimulator")
        -> VyronScreenshotSource {
        VyronScreenshotSource(
            id: "window-\(identifier)", name: "Simulator \(identifier)",
            target: .window(VyronScreenshotWindowTarget(
                windowID: identifier, processID: 42, bundleIdentifier: applicationID
            ))
        )
    }

    private func listCall() -> DevelopmentToolCall {
        DevelopmentToolCall(
            name: "vyron_mac_windows", arguments: ["application_id": .string("com.apple.iphonesimulator")]
        )
    }

    private func captureCall(_ sourceID: String) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "vyron_mac_screenshot", arguments: ["source_id": .string(sourceID)])
    }
}
