import XCTest
@testable import Vyron

@MainActor
final class VyronConversationModeLifecycleTests: XCTestCase {
    func testStoppedFirstResponseRetainsItsMode() async throws {
        for mode in [ComposerMode.chat, .plan] {
            let test = VyronQueueTestHarness()
            defer { test.cleanUp() }
            test.model.computerWork.automaticRequestRouting = false
            test.model.composer.mode = mode
            test.send("Explain this concept.")
            try await waitUntil { await test.provider.requests.count == 1 }

            test.model.stopGeneration()
            try await waitUntil { await test.provider.cancellations == 1 }
            test.model.selectComposerMode(mode == .chat ? .plan : .chat)

            XCTAssertTrue(test.model.isConversationModeLocked)
            XCTAssertEqual(test.model.composer.mode, mode)
            XCTAssertEqual(test.model.selectedConversation?.mode, mode.rawValue)
            XCTAssertEqual(test.model.messages.last?.activity?.state, .stopped)
        }
    }

    func testFailedFirstResponseRetainsItsMode() async throws {
        for mode in [ComposerMode.chat, .plan] {
            let test = VyronQueueTestHarness()
            defer { test.cleanUp() }
            test.model.computerWork.automaticRequestRouting = false
            test.model.composer.mode = mode
            test.send("Explain this concept.")
            try await waitUntil { await test.provider.requests.count == 1 }

            await test.provider.fail(0)
            try await waitUntil { !test.model.foregroundRun.isGenerating }
            test.model.composer.mode = mode == .chat ? .plan : .chat

            XCTAssertTrue(test.model.isConversationModeLocked)
            XCTAssertEqual(test.model.composer.mode, mode)
            XCTAssertEqual(test.model.selectedConversation?.mode, mode.rawValue)
            XCTAssertEqual(test.model.messages.last?.activity?.state, .failed)
        }
    }

    func testQueuedFollowUpPreservesTheStartingMode() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.model.computerWork.automaticRequestRouting = false
        test.send("Explain this concept.")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.send("Give me an example.")
        test.model.composer.mode = .plan
        XCTAssertEqual(test.model.composer.mode, .chat)

        await test.provider.complete(0, answer: "An explanation.")
        try await waitUntil { await test.provider.requests.count == 2 }
        await test.provider.complete(1, answer: "An example.")
        try await waitUntil { !test.model.foregroundRun.isGenerating }

        XCTAssertEqual(test.model.selectedConversation?.mode, ComposerMode.chat.rawValue)
        XCTAssertTrue(test.model.isConversationModeLocked)
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
        XCTAssertEqual(test.model.messages.filter { $0.role == "user" }.count, 2)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Conversation mode lifecycle did not reach its expected state.")
        throw CancellationError()
    }
}
