import Foundation
import XCTest
@testable import Vyron
import VyronCore

@MainActor
final class VyronMacWorkScreenshotTestHarness {
    let capture = VyronScreenshotPickerTestCapture()
    let state = VyronMacWorkScreenshotTestState()
    let tools: VyronMacWorkScreenshots

    init() {
        let capture = capture
        let state = state
        tools = VyronMacWorkScreenshots(
            captureService: capture,
            validateCurrent: { state.isCurrent },
            onCaptured: {
                if state.failPublication { throw CocoaError(.fileWriteUnknown) }
                state.capturedImages.append($0)
            }
        )
    }

    func list(
        _ sources: [VyronScreenshotSource], applicationID: String = "com.apple.iphonesimulator"
    ) async throws -> DevelopmentExternalResult {
        let requestCount = capture.sourceRequests.count
        let task = Task {
            try await tools.execute(DevelopmentToolCall(
                name: "vyron_mac_windows", arguments: ["application_id": .string(applicationID)]
            ))
        }
        try await waitUntil { self.capture.sourceRequests.count == requestCount + 1 }
        capture.sourceRequests[requestCount].resume(returning: sources)
        return try await task.value
    }

    func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The in-memory Work screenshot operation did not finish.")
        throw CancellationError()
    }
}
