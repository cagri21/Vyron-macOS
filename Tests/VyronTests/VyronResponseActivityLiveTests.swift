import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronResponseActivityLiveTests: XCTestCase {
    func testOnlyExactActiveResponseInSelectedConversationIsLive() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let earlier = answer()
        let current = answer()
        var first = conversation(messages: [earlier, current])
        first.mode = ComposerMode.chat.rawValue
        let sameMessageIDInOtherChat = ChatMessage(
            id: current.id, role: "assistant", content: "Other chat", activity: ResponseActivity()
        )
        let other = conversation(messages: [sameMessageIDInOtherChat])
        test.model.conversations = [first, other]
        test.model.selectedConversationID = first.id
        let response = VyronResponseIdentity(
            generationID: UUID(),
            conversationID: first.id, messageID: current.id
        )
        test.model.foregroundRun.begin(response)

        XCTAssertTrue(test.model.isResponseActivityLive(messageID: current.id))
        XCTAssertFalse(test.model.isResponseActivityLive(messageID: earlier.id))
        XCTAssertFalse(test.model.isResponseActivityLive(messageID: UUID()))
        test.model.selectedConversationID = other.id
        XCTAssertFalse(test.model.isResponseActivityLive(messageID: sameMessageIDInOtherChat.id))
        test.model.selectedConversationID = first.id
        test.model.foregroundRun.complete(response.generationID)
        XCTAssertFalse(test.model.isResponseActivityLive(messageID: current.id))
    }

    func testLegacyAndTerminalActivitiesAreNeverLiveEvenWhenResponseIdentityMatches() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let legacy = ChatMessage(role: "assistant", content: "Legacy answer")
        var messages = [legacy]
        for state in [ResponseActivity.State.completed, .stopped, .failed] {
            var activity = ResponseActivity()
            activity.finish(state)
            messages.append(ChatMessage(role: "assistant", content: "Terminal answer", activity: activity))
        }
        let selected = conversation(messages: messages)
        test.model.conversations = [selected]
        test.model.selectedConversationID = selected.id
        for message in messages {
            let response = VyronResponseIdentity(
                generationID: UUID(),
                conversationID: selected.id, messageID: message.id
            )
            test.model.foregroundRun.begin(response)
            XCTAssertFalse(test.model.isResponseActivityLive(messageID: message.id))
            test.model.foregroundRun.complete(response.generationID)
        }
    }

    func testComputerWorkAnimatesOnlyItsOwningWorkingResponse() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let earlier = answer()
        let selected = conversation(messages: [earlier])
        test.model.conversations = [selected]
        test.model.selectedConversationID = selected.id
        test.model.modelSelection.activeConnectionID = nil
        test.model.modelSelection.connectionProfiles = []
        test.model.modelSelection.configuredInferenceClient = test.provider
        test.model.modelSelection.models = [LocalModel(name: "control-test", size: 1)]
        test.model.modelSelection.selectedModel = "control-test"
        test.model.modelSelection.automaticModelSelection = false
        test.model.computerWork.automaticRequestRouting = true
        test.model.modelSelection.isConnected = true
        test.model.composer.draft = "Open Safari"
        test.model.send()
        try await test.waitUntil { test.model.computerWork.pendingAgentGoal != nil }
        let goal = try XCTUnwrap(test.model.computerWork.pendingAgentGoal)

        XCTAssertFalse(test.model.isResponseActivityLive(messageID: earlier.id))
        XCTAssertTrue(test.model.computerWork.isComputerWorkActive)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertTrue(test.model.isResponseActivityLive(messageID: goal.messageID))
        test.model.reportAgentProgress(requestID: goal.id, state: "Completed fixture", trace: [], finished: true)
        XCTAssertFalse(test.model.isResponseActivityLive(messageID: goal.messageID))
    }

    func testScheduledRunAnimatesOnlyItsOwningConversationWhileProviderIsPending() async throws {
        let test = try VyronScheduledAppModelTestHarness()
        addTeardownBlock { try await test.cleanUp() }
        let foreground = try XCTUnwrap(test.model.selectedConversationID)
        let task = test.task()
        XCTAssertTrue(test.model.scheduledTasks.save(task))
        test.model.scheduledTasks.runNow(task.id)
        try await waitUntil { await test.provider.requests.count == 1 }
        let run = try XCTUnwrap(test.model.scheduledTasks.tasks.first?.progress.lastRun)
        let resultID = try XCTUnwrap(run.output.conversationID)
        let result = try XCTUnwrap(test.model.conversations.first { $0.id == resultID })
        let answerID = try XCTUnwrap(result.messages.last?.id)

        XCTAssertEqual(test.model.selectedConversationID, foreground)
        XCTAssertFalse(test.model.isResponseActivityLive(messageID: answerID))
        test.model.selectConversation(resultID)
        XCTAssertTrue(test.model.isResponseActivityLive(messageID: answerID))
        test.model.selectConversation(foreground)
        XCTAssertFalse(test.model.isResponseActivityLive(messageID: answerID))
        await test.provider.complete("The scheduled answer.")
        await test.model.scheduledTasks.waitForCurrentRun()
        test.model.selectConversation(resultID)
        XCTAssertFalse(test.model.isResponseActivityLive(messageID: answerID))
    }

    private func answer() -> ChatMessage {
        ChatMessage(role: "assistant", content: "Working answer", activity: ResponseActivity())
    }

    private func conversation(messages: [ChatMessage]) -> Conversation {
        var conversation = Conversation(title: "Timing fixture", workspacePath: nil)
        conversation.mode = ComposerMode.chat.rawValue
        conversation.messages = messages
        return conversation
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The scheduled timing operation did not reach its expected state.")
        throw CancellationError()
    }
}
