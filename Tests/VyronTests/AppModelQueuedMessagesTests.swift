import Foundation
import XCTest
@testable import Vyron
import VyronCore

@MainActor
final class AppModelQueuedMessagesTests: XCTestCase {
    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Queued-message lifecycle did not reach its expected state")
        throw CancellationError()
    }

    func testQueueWaitsThenRunsFIFOWithoutReplacingUnsentDraft() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.send("Original task")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.send("First follow-up")
        test.send("Second follow-up")
        XCTAssertEqual(test.model.queuedMessages.map(\.content), ["First follow-up", "Second follow-up"])
        let firstID = try XCTUnwrap(test.model.queuedMessages.first?.id)
        let secondID = try XCTUnwrap(test.model.queuedMessages.last?.id)
        let beforeCompletion = await test.provider.requests.count
        XCTAssertEqual(beforeCompletion, 1)
        test.model.composer.draft = "Unsent work in progress"
        await test.provider.complete(0, answer: "Original answer")
        try await waitUntil { await test.provider.requests.count == 2 }
        XCTAssertEqual(test.model.composer.draft, "Unsent work in progress")
        XCTAssertEqual(test.model.queuedMessages.map(\.id), [secondID])
        XCTAssertEqual(test.model.messages.filter { $0.id == firstID }.map(\.content), ["First follow-up"])
        let firstMessages = await test.provider.requests[1]
        XCTAssertEqual(firstMessages.filter { $0.role == "user" }.map(\.content), ["Original task", "First follow-up"])
        await test.provider.complete(1, answer: "First answer")
        try await waitUntil { await test.provider.requests.count == 3 }
        let secondMessages = await test.provider.requests[2]
        XCTAssertEqual(secondMessages.last?.content, "Second follow-up")
        XCTAssertEqual(test.model.messages.filter { $0.id == secondID }.map(\.content), ["Second follow-up"])
        XCTAssertEqual(test.model.composer.draft, "Unsent work in progress")
        await test.provider.complete(2, answer: "Second answer")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
    }

    func testFailedQueueHandoffKeepsMessagePendingAndCanBeRetried() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.send("Original task")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.send("First follow-up")
        test.send("Second follow-up")
        let firstID = try XCTUnwrap(test.model.queuedMessages.first?.id)
        let secondID = try XCTUnwrap(test.model.queuedMessages.last?.id)
        let conversationID = try XCTUnwrap(test.model.selectedConversationID)
        test.model.conversations[0].contextByMessageID = [firstID.uuidString: "Unacknowledged steering context"]
        test.model.composer.draft = "Keep this draft"

        test.model.historyIsWritable = false
        await test.provider.complete(0, answer: "Original answer")
        try await waitUntil { test.model.errorMessage == VyronStatusText.historyUnavailable }
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertEqual(test.model.queuedMessages.map(\.id), [firstID, secondID])
        XCTAssertFalse(test.model.messages.contains { $0.id == firstID })
        XCTAssertEqual(test.model.composer.draft, "Keep this draft")
        let requestsAfterBlockedHandoff = await test.provider.requests.count
        XCTAssertEqual(requestsAfterBlockedHandoff, 1)

        test.model.historyIsWritable = true
        test.model.steerQueuedMessage(firstID)
        try await waitUntil { await test.provider.requests.count == 2 }
        let history = try test.model.historyStore.load()
        let persistedConversation = try XCTUnwrap(history.first { $0.id == conversationID })
        XCTAssertEqual(persistedConversation.queuedMessages?.map(\.id), [secondID])
        XCTAssertEqual(persistedConversation.messages.filter { $0.id == firstID }.map(\.content), ["First follow-up"])
        XCTAssertNil(persistedConversation.contextByMessageID?[firstID.uuidString])
        XCTAssertEqual(test.model.composer.draft, "Keep this draft")

        await test.provider.fail(1)
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertEqual(test.model.messages.filter { $0.id == firstID }.count, 1)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .failed)
        XCTAssertEqual(test.model.queuedMessages.map(\.id), [secondID])
    }

    func testEditSaveCancelAndDeletePreserveExistingDraft() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.send("Original task")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.send("Pending question")
        let id = try XCTUnwrap(test.model.queuedMessages.first?.id)
        test.model.composer.draft = "Existing draft"
        test.model.editQueuedMessage(id)
        XCTAssertTrue(test.model.composer.isEditingQueuedMessage)
        XCTAssertEqual(test.model.composer.draft, "Pending question")
        test.model.composer.draft = "Abandoned revision"
        test.model.composer.cancelQueuedMessageEdit()
        XCTAssertEqual(test.model.composer.draft, "Existing draft")
        XCTAssertEqual(test.model.queuedMessages.first?.content, "Pending question")
        test.model.editQueuedMessage(id)
        test.model.composer.draft = "Saved revision"
        test.model.send()
        XCTAssertFalse(test.model.composer.isEditingQueuedMessage)
        XCTAssertEqual(test.model.composer.draft, "Existing draft")
        XCTAssertEqual(test.model.queuedMessages.first?.content, "Saved revision")
        test.model.editQueuedMessage(id)
        test.model.deleteQueuedMessage(id)
        XCTAssertFalse(test.model.composer.isEditingQueuedMessage)
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
        XCTAssertEqual(test.model.composer.draft, "Existing draft")
    }

    func testStopRetainsQueueAndDoesNotStartFollowUpUntilRequested() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.send("Original task")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.send("Saved for later")
        let id = try XCTUnwrap(test.model.queuedMessages.first?.id)
        test.model.stopGeneration()
        try await waitUntil { await test.provider.cancellations == 1 }
        XCTAssertEqual(test.model.queuedMessages.first?.content, "Saved for later")
        let count = await test.provider.requests.count
        XCTAssertEqual(count, 1)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        test.model.steerQueuedMessage(id)
        try await waitUntil { await test.provider.requests.count == 2 }
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
    }

    func testFailureRetainsQueueAndUserCanRetryIt() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.send("Original task")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.send("Follow up after failure")
        let id = try XCTUnwrap(test.model.queuedMessages.first?.id)
        await test.provider.fail(0)
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertEqual(test.model.messages.last?.activity?.state, .failed)
        XCTAssertEqual(test.model.queuedMessages.count, 1)
        let count = await test.provider.requests.count
        XCTAssertEqual(count, 1)
        test.model.steerQueuedMessage(id)
        try await waitUntil { await test.provider.requests.count == 2 }
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
        XCTAssertNil(test.model.errorMessage)
    }

    func testSwitchingKeepsQueueWithOriginalChatAndStopOnlyCancelsSelectedReply() async throws {
        let test = VyronQueueTestHarness()
        defer {
            for id in test.model.conversations.map(\.id) where test.model.isSidebarConversationActive(id) {
                test.model.selectConversation(id)
                test.model.stopGeneration()
            }
            test.cleanUp()
        }
        test.model.computerWork.automaticRequestRouting = false
        test.send("Original task")
        try await waitUntil { test.model.messages.last?.content == "Partial answer 0" }
        let firstID = try XCTUnwrap(test.model.selectedConversationID)
        test.send("Only for original chat")
        var other = Conversation(title: "Other chat", workspacePath: nil)
        other.mode = ComposerMode.chat.rawValue
        let previousAnswer = ChatMessage(role: "assistant", content: "Previous answer in other chat")
        other.messages = [ChatMessage(role: "user", content: "Earlier question"), previousAnswer]
        test.model.conversations.append(other)
        test.model.selectConversation(other.id)
        XCTAssertEqual(test.model.messages.last, previousAnswer)
        XCTAssertTrue(test.model.isSidebarConversationActive(firstID))
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
        XCTAssertEqual(test.model.conversations.first { $0.id == firstID }?.queuedMessages?.first?.content,
            "Only for original chat")
        test.send("Other chat task")
        try await waitUntil { await test.provider.requests.count == 2 }
        let request = await test.provider.requests[1]
        XCTAssertFalse(request.contains { $0.content == "Only for original chat" })
        XCTAssertEqual(request.last?.content, "Other chat task")

        test.model.selectConversation(firstID)
        test.model.stopGeneration()
        try await waitUntil { await test.provider.cancellations == 1 }
        XCTAssertEqual(test.model.queuedMessages.first?.content, "Only for original chat")
        XCTAssertEqual(test.model.messages.last?.activity?.state, .stopped)
        XCTAssertTrue(test.model.isSidebarConversationActive(other.id))

        await test.provider.complete(1, answer: "Other chat answer")
        try await waitUntil { !test.model.isSidebarConversationActive(other.id) }
        XCTAssertEqual(test.model.messages.last?.content, "Partial answer 0")
        let otherAnswer = test.model.conversations.first { $0.id == other.id }?.messages.last
        XCTAssertEqual(otherAnswer?.content, "Other chat answer")
        XCTAssertEqual(otherAnswer?.activity?.state, .completed)
    }

    func testQueuedMessagesReopenWithoutSendingAndOldHistoryDecodes() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.send("Original task")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.send("Persist this follow-up")
        let originalID = try XCTUnwrap(test.model.selectedConversationID)
        test.model.stopGeneration()
        let reopened = AppModel(historyDirectory: test.directory)
        reopened.selectConversation(originalID)
        XCTAssertEqual(reopened.queuedMessages.first?.content, "Persist this follow-up")
        XCTAssertFalse(reopened.foregroundRun.isGenerating)
        var legacy = Conversation(title: "Legacy chat", workspacePath: nil)
        legacy.messages = [ChatMessage(role: "user", content: "Old question")]
        let oldData = try JSONEncoder().encode([legacy])
        let restored = try JSONDecoder().decode([Conversation].self, from: oldData)
        XCTAssertNil(restored.first?.queuedMessages)
        XCTAssertEqual(restored.first?.messages.first?.content, "Old question")
    }

    func testChatSteeringPreservesOriginalAndPartialHistoryRejectsLateTokens() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.send("Write the original implementation")
        try await waitUntil { test.model.messages.last?.content == "Partial answer 0" }
        test.send("Keep the change inside this feature")
        let id = try XCTUnwrap(test.model.queuedMessages.first?.id)
        test.model.steerQueuedMessage(id)
        try await waitUntil {
            let requestCount = await test.provider.requests.count
            let cancellationCount = await test.provider.cancellations
            return requestCount == 2 && cancellationCount == 1
        }
        let request = await test.provider.requests[1]
        XCTAssertEqual(request.first?.content, "Write the original implementation")
        XCTAssertTrue(request.contains { $0.role == "assistant" && $0.content == "Partial answer 0" })
        XCTAssertEqual(request.last?.content, "Keep the change inside this feature")
        XCTAssertEqual(test.model.messages[1].activity?.state, .stopped)
        XCTAssertFalse(test.model.messages.contains { $0.content.contains("STALE_CANCELLED_TOKEN") })
        await test.provider.complete(1, answer: "Updated implementation")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertEqual(test.model.messages.last?.content, "Updated implementation")
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
    }

    func testTurningOffQueueSteersNewMessageAndNewTaskKeepsPendingInOldChat() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.send("Original task")
        try await waitUntil { await test.provider.requests.count == 1 }
        test.model.composer.queueMessages = false
        test.send("Apply this now")
        try await waitUntil { await test.provider.requests.count == 2 }
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
        let request = await test.provider.requests[1]
        XCTAssertEqual(request.last?.content, "Apply this now")
        test.model.composer.queueMessages = true
        test.send("Pending in old chat")
        let originalID = try XCTUnwrap(test.model.selectedConversationID)
        test.model.newConversation()
        XCTAssertNil(test.model.selectedConversationID)
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
        XCTAssertEqual(test.model.conversations.first { $0.id == originalID }?.queuedMessages?.first?.content,
            "Pending in old chat")
    }

    func testAgentAcknowledgesSteeringOnceAtBoundaryAndRunsOtherQueuedMessageLater() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let project = test.directory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("Small project notes.\n".utf8).write(to: project.appendingPathComponent("README.md"))
        await test.model.loadWorkspace(project)
        test.model.composer.mode = .agent
        test.send("Inspect the existing project")
        try await waitUntil { await test.provider.developmentRequests.count == 1 }
        test.send("Explain the project without modifying it")
        let steeringID = try XCTUnwrap(test.model.queuedMessages.first?.id)
        test.send("Then list the next validation steps")
        test.model.steerQueuedMessage(steeringID)
        XCTAssertEqual(test.model.queuedMessages.count, 2)
        XCTAssertTrue(test.model.composer.pendingSteeringIDs.contains(steeringID))
        XCTAssertFalse(test.model.messages.contains { $0.id == steeringID })
        await Task.yield()
        let requestCount = await test.provider.developmentRequests.count
        XCTAssertEqual(requestCount, 1, "Steering must not launch a concurrent development run")
        await test.provider.completeDevelopment(0, message: DevelopmentMessage(
            role: "assistant", content: "Initial project explanation"
        ))
        try await waitUntil { await test.provider.developmentRequests.count == 2 }
        XCTAssertEqual(test.model.queuedMessages.map(\.content), ["Then list the next validation steps"])
        XCTAssertFalse(test.model.composer.pendingSteeringIDs.contains(steeringID))
        let transcript = test.model.messages
        XCTAssertEqual(transcript.filter { $0.id == steeringID }.count, 1)
        let updateIndex = try XCTUnwrap(transcript.firstIndex { $0.id == steeringID })
        XCTAssertEqual(transcript[updateIndex].role, "user")
        XCTAssertEqual(transcript.last?.role, "assistant")
        XCTAssertLessThan(updateIndex, transcript.count - 1)
        let correctedRequest = await test.provider.developmentRequests[1]
        XCTAssertTrue(correctedRequest.contains {
            $0.role == "user" && $0.content == "Explain the project without modifying it"
        })
        XCTAssertFalse(correctedRequest.contains { $0.content == "Then list the next validation steps" })
        await test.provider.completeDevelopment(1, message: DevelopmentMessage(
            role: "assistant", content: "The project is a small application. No files were modified."
        ))
        try await waitUntil { await test.provider.developmentRequests.count == 3 }
        XCTAssertEqual(test.model.messages.filter { $0.id == steeringID }.count, 1)
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
        let queuedRequest = await test.provider.developmentRequests[2]
        XCTAssertTrue(queuedRequest.contains { $0.content.contains("Then list the next validation steps") })
        await test.provider.completeDevelopment(2, message: DevelopmentMessage(
            role: "assistant", content: "Run the existing checks."
        ))
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertEqual(test.model.messages.filter { $0.id == steeringID }.count, 1)
        XCTAssertEqual(test.model.messages.filter { $0.role == "user" }.count, 3)
    }

    func testStoppingAgentBeforeSteeringBoundaryRetainsUnappliedUpdate() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let project = test.directory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("Small project notes.\n".utf8).write(to: project.appendingPathComponent("README.md"))
        await test.model.loadWorkspace(project)
        test.model.composer.mode = .agent
        test.send("Inspect the project")
        try await waitUntil { await test.provider.developmentRequests.count == 1 }
        test.send("Restrict the scope to documentation")
        let id = try XCTUnwrap(test.model.queuedMessages.first?.id)
        test.model.steerQueuedMessage(id)
        test.model.stopGeneration()
        try await waitUntil {
            let count = await test.provider.developmentCancellations
            return count == 1 && !test.model.foregroundRun.isStoppingDevelopment
        }
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertEqual(test.model.queuedMessages.first?.id, id)
        XCTAssertTrue(test.model.composer.pendingSteeringIDs.isEmpty)
        XCTAssertFalse(test.model.messages.contains { $0.id == id })
        let requestCount = await test.provider.developmentRequests.count
        XCTAssertEqual(requestCount, 1)
    }
}
