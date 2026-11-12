import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronNewTaskDuringWorkTests: XCTestCase {
    func testNewTaskDuringWorkOpensMainChatAndPreservesBothReplies() async throws {
        let test = VyronQueueTestHarness()
        let model = test.model
        defer { cleanUp(test) }
        let project = try await loadProject(test, mode: .agent)
        let originalRequest = "Inspect the existing project without editing it."
        test.send(originalRequest)
        try await waitUntil { await test.provider.developmentRequests.count == 1 }
        let work = try XCTUnwrap(model.foregroundRun.activeResponse)
        let approval = CommandApproval(command: "swift test", reason: "Review the proposed project check.")
        let review = Task { await model.reviewDevelopmentCommand(approval, generationID: work.generationID) }
        defer {
            model.respondToCommandApproval(false, approvalID: approval.id)
            review.cancel()
        }
        try await waitUntil { model.interactions.pendingCommandApproval?.id == approval.id }

        model.requestNewTask()

        XCTAssertNil(model.selectedConversationID)
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertEqual(model.composer.mode, .chat)
        XCTAssertTrue(model.newSideChatSessions.isEmpty)
        XCTAssertEqual(model.foregroundRun.response(in: work.conversationID), work)
        XCTAssertTrue(model.isSidebarConversationActive(work.conversationID))
        XCTAssertEqual(model.interactions.pendingCommandApproval?.id, approval.id)
        XCTAssertNil(model.selectedCommandApproval)
        XCTAssertEqual(model.notificationCommandOwner?.conversationID, work.conversationID)
        model.respondToCommandApproval(true, approvalID: approval.id)
        XCTAssertEqual(model.interactions.pendingCommandApproval?.id, approval.id)
        XCTAssertFalse(model.canAcceptConversationMessage(in: .agent))

        let question = "Can you explain how a cache works?"
        test.send(question)
        try await waitUntil { await test.provider.requests.count == 1 }
        let newChat = try XCTUnwrap(model.foregroundRun.activeResponse)
        XCTAssertNotEqual(newChat.conversationID, work.conversationID)
        let request = await test.provider.requests[0]
        XCTAssertEqual(request.count, 1)
        XCTAssertTrue(request.first?.content.hasPrefix(question) == true)
        XCTAssertFalse(request.contains { $0.content.contains(originalRequest) })

        model.requestSidebarConversation(work.conversationID)
        try await waitUntil { model.workspaceState.workspaceURL == project && !model.workspaceState.isLoadingWorkspace }
        XCTAssertEqual(model.selectedConversationID, work.conversationID)
        XCTAssertEqual(model.composer.mode, .agent)
        XCTAssertEqual(model.foregroundRun.activeResponse, work)
        XCTAssertEqual(model.foregroundRun.response(in: newChat.conversationID), newChat)
        XCTAssertEqual(model.selectedCommandApproval?.id, approval.id)
        model.respondToCommandApproval(true, approvalID: approval.id)
        try await waitUntil { model.interactions.pendingCommandApproval == nil }
        let approved = await review.value
        XCTAssertTrue(approved)

        model.requestSidebarConversation(newChat.conversationID)
        XCTAssertEqual(model.foregroundRun.activeResponse, newChat)
        await test.provider.completeDevelopment(0, message: DevelopmentMessage(
            role: "assistant", content: "Project review finished."
        ))
        try await waitUntil { !model.isSidebarConversationActive(work.conversationID) }
        let workReply = model.conversations.first { $0.id == work.conversationID }?.messages.last
        XCTAssertEqual(workReply?.activity?.state, .completed)
        XCTAssertTrue(workReply?.content.contains("Project review finished.") == true)
        XCTAssertEqual(model.messages.last?.id, newChat.messageID)
        XCTAssertEqual(model.messages.last?.activity?.state, .working)

        await test.provider.complete(0, answer: "A cache saves copies for faster access.")
        try await waitUntil { !model.foregroundRun.isGenerating }
        XCTAssertEqual(model.messages.last?.activity?.state, .completed)
        XCTAssertEqual(model.messages.last?.content, "A cache saves copies for faster access.")
    }

    func testCompletingAnotherChatPreservesWorkQuestionUntilOriginalChatAnswersIt() async throws {
        let test = VyronQueueTestHarness()
        let model = test.model
        defer { cleanUp(test) }
        _ = try await loadProject(test, mode: .agent)
        test.send("Review the project documentation.")
        try await waitUntil { await test.provider.developmentRequests.count == 1 }
        let work = try XCTUnwrap(model.foregroundRun.activeResponse)
        let inputTool = DevelopmentToolCall(name: "request_user_input", arguments: [
            "questions": .array([.object([
                "id": .string("scope"), "question": .string("Which documentation should I review?")
            ])])
        ])
        await test.provider.completeDevelopment(0, message: DevelopmentMessage(
            role: "assistant", toolCalls: [inputTool]
        ))
        try await waitUntil { model.selectedUserInputRequest != nil }
        let input = try XCTUnwrap(model.selectedUserInputRequest)

        model.requestNewTask()
        test.send("What is the difference between an array and a dictionary?")
        try await waitUntil { await test.provider.requests.count == 1 }
        let otherID = try XCTUnwrap(model.selectedConversationID)
        let otherAnswer = "A dictionary maps keys to values."
        await test.provider.complete(0, answer: otherAnswer)
        try await waitUntil { !model.isSidebarConversationActive(otherID) }
        XCTAssertEqual(model.messages.last?.content, otherAnswer)
        XCTAssertEqual(model.interactions.pendingUserInput?.id, input.id)
        XCTAssertNil(model.selectedUserInputRequest)
        XCTAssertTrue(model.isSidebarConversationActive(work.conversationID))

        let answer = VyronUserInputResponse(requestID: input.id, answers: [
            VyronUserInputAnswer(questionID: "scope", value: "README only")
        ])
        model.respondToUserInput(answer)
        XCTAssertEqual(model.interactions.pendingUserInput?.id, input.id)
        model.requestSidebarConversation(work.conversationID)
        XCTAssertEqual(model.selectedUserInputRequest?.id, input.id)
        model.respondToUserInput(answer)
        try await waitUntil { await test.provider.developmentRequests.count == 2 }
        let resumedRequest = await test.provider.developmentRequests[1]
        XCTAssertTrue(resumedRequest.contains {
            $0.toolName == inputTool.function.name && $0.content.contains("README only")
        })

        model.requestSidebarConversation(otherID)
        let workAnswer = "The README explains the project."
        await test.provider.completeDevelopment(1, message: DevelopmentMessage(role: "assistant", content: workAnswer))
        try await waitUntil { !model.isSidebarConversationActive(work.conversationID) }
        let reply = model.conversations.first { $0.id == work.conversationID }?.messages.last
        XCTAssertEqual(reply?.activity?.state, .completed)
        XCTAssertTrue(reply?.content.contains(workAnswer) == true)
        XCTAssertEqual(model.selectedConversationID, otherID)
        XCTAssertEqual(model.messages.last?.content, otherAnswer)
    }

    func testSidebarChatDuringProjectPlanSwitchesMainViewAndKeepsPlanRunning() async throws {
        let test = VyronQueueTestHarness()
        let model = test.model
        defer { cleanUp(test) }
        _ = try await loadProject(test, mode: .plan)
        var other = Conversation(title: "Existing Chat", workspacePath: nil)
        other.mode = ComposerMode.chat.rawValue
        other.messages = [ChatMessage(role: .user, content: "An earlier question.")]
        model.conversations.append(other)
        test.send("Outline a plan to review this project.")
        try await waitUntil { await test.provider.developmentRequests.count == 1 }
        let plan = try XCTUnwrap(model.foregroundRun.activeResponse)

        model.requestSidebarConversation(other.id)

        XCTAssertEqual(model.selectedConversationID, other.id)
        XCTAssertEqual(model.messages, other.messages)
        XCTAssertTrue(model.newSideChatSessions.isEmpty)
        XCTAssertNil(model.workspaceState.workspaceURL)
        XCTAssertEqual(model.composer.mode, .chat)
        XCTAssertEqual(model.foregroundRun.response(in: plan.conversationID), plan)
        await test.provider.completeDevelopment(0, message: DevelopmentMessage(
            role: "assistant", content: "Review the project notes, then check the existing tests."
        ))
        try await waitUntil { !model.isSidebarConversationActive(plan.conversationID) }
        let reply = model.conversations.first { $0.id == plan.conversationID }?.messages.last
        XCTAssertEqual(reply?.activity?.state, .completed)
        XCTAssertEqual(model.selectedConversationID, other.id)
        XCTAssertEqual(model.messages, other.messages)
        XCTAssertNil(model.workspaceState.workspaceURL)
    }

    func testStopOnlyCancelsReselectedWorkWhileAnotherChatKeepsAnswering() async throws {
        let test = VyronQueueTestHarness()
        let model = test.model
        defer { cleanUp(test) }
        _ = try await loadProject(test, mode: .agent)
        test.send("Review the project without making changes.")
        try await waitUntil { await test.provider.developmentRequests.count == 1 }
        let work = try XCTUnwrap(model.foregroundRun.activeResponse)

        model.requestNewTask()
        test.send("Explain why a dictionary needs keys.")
        try await waitUntil { await test.provider.requests.count == 1 }
        let other = try XCTUnwrap(model.foregroundRun.activeResponse)
        model.requestSidebarConversation(work.conversationID)
        XCTAssertEqual(model.foregroundRun.activeResponse, work)

        model.stopGeneration()

        try await waitUntil { await test.provider.developmentCancellations == 1 }
        XCTAssertEqual(model.messages.last?.activity?.state, .stopped)
        XCTAssertEqual(model.foregroundRun.response(in: other.conversationID), other)
        await test.provider.complete(0, answer: "A dictionary uses keys to look up values.")
        try await waitUntil { !model.isSidebarConversationActive(other.conversationID) }
        let otherReply = model.conversations.first { $0.id == other.conversationID }?.messages.last
        XCTAssertEqual(otherReply?.activity?.state, .completed)
        XCTAssertEqual(otherReply?.content, "A dictionary uses keys to look up values.")
        let chatCancellations = await test.provider.cancellations
        XCTAssertEqual(chatCancellations, 0)
    }

    func testNewTaskDuringOrdinaryChatKeepsReplyRunningInMainWindowHistory() async throws {
        let test = VyronQueueTestHarness()
        let model = test.model
        defer { cleanUp(test) }
        model.computerWork.automaticRequestRouting = false
        test.send("Explain the difference between a list and a set.")
        try await waitUntil { await test.provider.requests.count == 1 }
        let originalID = try XCTUnwrap(model.selectedConversationID)

        model.requestNewTask()

        XCTAssertNil(model.selectedConversationID)
        XCTAssertTrue(model.newSideChatSessions.isEmpty)
        XCTAssertTrue(model.isSidebarConversationActive(originalID))
        await test.provider.complete(0, answer: "A list preserves order. A set stores unique elements.")
        try await waitUntil { !model.isSidebarConversationActive(originalID) }
        model.requestSidebarConversation(originalID)
        XCTAssertEqual(model.selectedConversationID, originalID)
        XCTAssertEqual(model.messages.last?.activity?.state, .completed)
        XCTAssertEqual(model.messages.last?.content, "A list preserves order. A set stores unique elements.")
    }

    private func cleanUp(_ test: VyronQueueTestHarness) {
        let model = test.model
        for id in model.conversations.map(\.id) where model.foregroundRun.response(in: id) != nil {
            model.selectConversation(id, loadProject: false)
            model.stopGeneration()
        }
        test.cleanUp()
    }

    private func loadProject(_ test: VyronQueueTestHarness, mode: ComposerMode) async throws -> URL {
        let project = test.directory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("Local project notes.\n".utf8).write(to: project.appendingPathComponent("README.md"))
        await test.model.loadWorkspace(project)
        test.model.composer.mode = mode
        test.model.computerWork.automaticRequestRouting = false
        return try XCTUnwrap(test.model.workspaceState.workspaceURL)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The conversation did not reach its expected state")
        throw CancellationError()
    }
}
