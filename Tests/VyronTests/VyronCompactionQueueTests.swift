import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronCompactionQueueTests: XCTestCase {
    func testQueuedCompactWaitsForCurrentReplyThenRunsBeforeFollowingMessage() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.send("Explain the existing project.")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.model.composer.queueMessages = false
        test.send("/compact")
        let compactID = try XCTUnwrap(test.model.queuedMessages.first?.id)
        XCTAssertFalse(test.model.canSteerQueuedMessage(try XCTUnwrap(test.model.queuedMessages.first)))
        test.model.steerQueuedMessage(compactID)
        let cancellations = await test.provider.cancellations
        XCTAssertEqual(cancellations, 0)
        test.model.composer.queueMessages = true
        test.send("/compact")
        test.send("What remains to be done?")
        test.model.composer.draft = "Keep this unsent draft."
        await test.provider.complete(0, answer: "The project has a settings feature. " + String(repeating: "Detail. ", count: 500))
        try await waitUntil { await test.provider.requests.count == 2 }
        XCTAssertEqual(test.model.queuedMessages.map(\.content), ["/compact", "What remains to be done?"])
        XCTAssertEqual(test.model.composer.draft, "Keep this unsent draft.")
        await test.provider.complete(1, answer: "The user asked about the existing settings project. Review the remaining tasks.")
        try await waitUntil { await test.provider.requests.count == 3 }
        let requests = await test.provider.requests
        XCTAssertTrue(requests[2].contains { $0.content.contains("Review the remaining tasks") })
        XCTAssertEqual(requests[2].last?.content, "What remains to be done?")
        XCTAssertFalse(requests[2].contains { $0.content == "/compact" })
        XCTAssertEqual(test.model.composer.draft, "Keep this unsent draft.")
        await test.provider.complete(2, answer: "Review the remaining tasks.")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
    }

    func testUnsentImagesRejectCompactBeforeQueuingAndRemainAttached() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.send("Original task")
        try await waitUntil { await test.provider.requests.count == 1 }
        let image = VyronImageAttachment(name: "Draft.png", mimeType: "image/png", data: Data([1, 2, 3]))
        test.model.composerAttachments.screenshotDraft.images = [image]
        test.send("/compact")
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
        XCTAssertEqual(test.model.errorMessage, VyronCompactionText.attachments)
        XCTAssertEqual(test.model.composerAttachments.screenshotDraft.images, [image])
        XCTAssertEqual(test.model.composer.draft, "/compact")
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Compaction queue did not reach the expected boundary.")
        throw CancellationError()
    }
}
