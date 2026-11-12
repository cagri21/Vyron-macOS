import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronNotificationAttentionTests: XCTestCase {
    func testPendingQuestionDateStaysStableAndReadingDoesNotResolveIt() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.model.computerWork.automaticRequestRouting = false
        test.send("Hold the response while I clarify the task.")
        try await waitUntil { await test.provider.requests.count == 1 }
        let generationID = try XCTUnwrap(test.model.foregroundRun.activeGeneration)
        let responseID = try XCTUnwrap(test.model.foregroundRun.activeResponse?.messageID)
        let request = VyronUserInputRequest(questions: [
            VyronUserInputQuestion(id: "color", question: "Which color should the interface use?")
        ])
        let waiting = Task {
            try await test.model.requestDevelopmentUserInput(request, generationID: generationID)
        }
        defer {
            test.model.cancelPendingUserInput()
            waiting.cancel()
        }
        try await waitUntil { test.model.interactions.pendingUserInput?.id == request.id }
        let first = try XCTUnwrap(test.model.notificationItems.first { $0.kind.isAttention })
        XCTAssertEqual(first.id.kind, .attention(VyronNotificationAttentionID(requestID: request.id)))
        XCTAssertTrue(test.model.markNotificationRead(first.id))
        XCTAssertTrue(test.model.openNotification(first))
        XCTAssertEqual(test.model.interactions.pendingUserInput?.id, request.id)
        XCTAssertEqual(test.model.foregroundRun.activeGeneration, generationID)

        let index = try XCTUnwrap(test.model.conversations.firstIndex {
            $0.id == test.model.selectedConversationID
        })
        let messageIndex = try XCTUnwrap(test.model.conversations[index].messages.firstIndex { $0.id == responseID })
        test.model.conversations[index].messages[messageIndex].activity?.record(
            "An unrelated public progress update", at: first.date.addingTimeInterval(60)
        )
        XCTAssertTrue(test.model.saveHistory())
        let updated = try XCTUnwrap(test.model.notificationItems.first { $0.id == first.id })
        XCTAssertEqual(updated.date, first.date)
        XCTAssertTrue(updated.isRead)
        XCTAssertTrue(updated.isPriority)
        XCTAssertFalse(updated.isUnread)
        XCTAssertEqual(test.model.interactions.pendingUserInput?.id, request.id)

        test.model.respondToUserInput(VyronUserInputResponse(requestID: request.id, answers: [
            VyronUserInputAnswer(questionID: "color", value: "Blue")
        ]))
        let received = try await waiting.value
        XCTAssertEqual(received.answers.first?.value, "Blue")
        XCTAssertNil(test.model.interactions.pendingUserInput)
        XCTAssertFalse(test.model.notificationItems.contains { $0.id == first.id })
        await test.provider.complete(0, answer: "The clarified task is ready.")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
    }

    func testCommandApprovalWithoutMatchingGenerationDoesNotBecomeAttentionForCurrentChat() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.model.computerWork.automaticRequestRouting = false
        test.send("Keep the current answer running.")
        try await waitUntil { await test.provider.requests.count == 1 }
        let approval = CommandApproval(command: "swift test", reason: "A stale request without its generation.")
        let review = Task {
            await test.model.interactions.reviewCommand(
                approval, generationID: UUID(), canPresent: { true }, willPresent: {}
            )
        }
        defer {
            test.model.respondToCommandApproval(false)
            review.cancel()
        }
        try await waitUntil { test.model.interactions.pendingCommandApproval?.id == approval.id }

        XCTAssertNil(test.model.notificationCommandOwner)
        XCTAssertFalse(test.model.notificationItems.contains { $0.kind.isAttention })
        XCTAssertEqual(test.model.notificationItems.filter(\.isLive).count, 1)
        XCTAssertEqual(test.model.unreadNotificationCount, 0)
        test.model.respondToCommandApproval(true, approvalID: approval.id)
        let approved = await review.value
        XCTAssertFalse(approved)
        await test.provider.complete(0, answer: "The unrelated current answer finished.")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
    }

    func testCancelledApprovalCannotResolveItsReplacementInTheSameGeneration() async throws {
        let interactions = VyronConversationInteractions(defaults: .standard)
        let generationID = UUID()
        let original = CommandApproval(command: "swift build", reason: "Build the project.")
        let replacement = CommandApproval(command: "swift test", reason: "Verify the project.")
        let first = Task {
            await interactions.reviewCommand(
                original, generationID: generationID, canPresent: { true }, willPresent: {}
            )
        }
        defer {
            interactions.respondToCommandApproval(false)
            first.cancel()
        }
        try await waitUntil { interactions.pendingCommandApproval?.id == original.id }

        let second = Task {
            await interactions.reviewCommand(
                replacement, generationID: generationID, canPresent: { true }, willPresent: { first.cancel() }
            )
        }
        defer { second.cancel() }
        try await waitUntil { interactions.pendingCommandApproval?.id == replacement.id }
        let firstApproved = await first.value
        XCTAssertFalse(firstApproved)
        interactions.respondToCommandApproval(false, approvalID: original.id)
        XCTAssertEqual(interactions.pendingCommandApproval?.id, replacement.id)
        interactions.respondToCommandApproval(true, approvalID: replacement.id)
        let replacementApproved = await second.value
        XCTAssertTrue(replacementApproved)
        XCTAssertNil(interactions.pendingCommandApproval)
    }

    func testVoiceActiveOtherChatUsesWindowFallbackWithoutInterruptingSpeech() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let speech = VyronSpeechTestService()
        let voice = VyronVoiceModel(service: speech)
        let model = AppModel(historyDirectory: test.directory, voice: voice)
        defer { voice.end() }
        var target = Conversation(title: "Target transcript", workspacePath: nil)
        var activity = ResponseActivity()
        activity.finish(.completed)
        target.messages = [ChatMessage(role: "assistant", content: "Saved result", activity: activity)]
        let foreground = Conversation(title: "Current voice chat", workspacePath: nil)
        model.conversations = [target, foreground]
        model.selectedConversationID = foreground.id
        for conversation in model.conversations { model.registerSidebarConversation(conversation.id) }
        XCTAssertTrue(model.saveHistory())
        let item = try XCTUnwrap(model.notificationItems.first { $0.conversationID == target.id })
        voice.previewVoice()
        XCTAssertEqual(voice.phase, .speaking)
        let speakingStops = speech.speakingStops

        XCTAssertFalse(model.openNotification(item))
        XCTAssertEqual(model.notificationWindowTarget(item), target.id)
        XCTAssertEqual(model.selectedConversationID, foreground.id)
        XCTAssertEqual(voice.phase, .speaking)
        XCTAssertEqual(speech.speakingStops, speakingStops)
        XCTAssertEqual(speech.utterances.count, 1)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The pending notification fixture did not reach its expected state.")
        throw CancellationError()
    }
}
