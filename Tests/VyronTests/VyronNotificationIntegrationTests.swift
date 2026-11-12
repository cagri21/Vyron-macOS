import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronNotificationIntegrationTests: XCTestCase {
    func testSavedTerminalNotificationReadPersistsAcrossReopen() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.model.computerWork.automaticRequestRouting = false
        test.send("Explain the current project.")
        try await waitUntil { await test.provider.requests.count == 1 }
        let responseID = try XCTUnwrap(test.model.foregroundRun.activeResponse?.messageID)
        let working = try XCTUnwrap(test.model.notificationItems.first)
        XCTAssertEqual(working.kind, .working)
        XCTAssertEqual(working.responseID, responseID)
        XCTAssertEqual(test.model.unreadNotificationCount, 0)

        await test.provider.complete(0, answer: "The project explanation is ready.")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        let terminal = try XCTUnwrap(test.model.notificationItems.first { $0.responseID == responseID })
        XCTAssertEqual(terminal.kind, .completed)
        XCTAssertTrue(terminal.isUnread)
        XCTAssertEqual(test.model.unreadNotificationCount, 1)
        XCTAssertNotEqual(terminal.id, working.id)
        XCTAssertTrue(test.model.openNotification(terminal))
        XCTAssertTrue(test.model.notifications.readState.isRead(terminal.id))
        XCTAssertEqual(test.model.unreadNotificationCount, 0)

        let reopened = AppModel(historyDirectory: test.directory)
        let persisted = try XCTUnwrap(reopened.notificationItems.first { $0.id == terminal.id })
        XCTAssertTrue(persisted.isRead)
        XCTAssertFalse(persisted.isUnread)
        XCTAssertEqual(reopened.unreadNotificationCount, 0)
        XCTAssertEqual(try reopened.notifications.readStore.load(), test.model.notifications.readState)
    }

    func testFailedFinalHistorySaveDoesNotCreatePhantomTerminalNotification() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.model.computerWork.automaticRequestRouting = false
        test.send("Explain the task before it is saved.")
        try await waitUntil { await test.provider.requests.count == 1 }
        let responseID = try XCTUnwrap(test.model.foregroundRun.activeResponse?.messageID)
        let history = test.directory.appendingPathComponent("conversations.json")
        let workingHistory = try Data(contentsOf: history)
        try FileManager.default.removeItem(at: history)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: false)

        await test.provider.complete(0, answer: "An answer whose final save is blocked.")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertFalse(test.model.notificationItems.contains { $0.responseID == responseID })
        XCTAssertEqual(test.model.unreadNotificationCount, 0)
        XCTAssertFalse(test.model.notifications.committedResponses.contains {
            $0.responseID == responseID && $0.kind == .completed
        })
        XCTAssertNotNil(test.model.errorMessage)

        try FileManager.default.removeItem(at: history)
        try workingHistory.write(to: history)
        XCTAssertEqual(test.model.messages.first { $0.id == responseID }?.activity?.state, .completed)
        XCTAssertTrue(test.model.saveHistory())
        XCTAssertTrue(test.model.notificationItems.contains {
            $0.responseID == responseID && $0.kind == .completed
        })
    }

    func testArchivedDeletedAndRemovedResponseTargetsCannotBeOpenedOrMarkedRead() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let archived = terminalChat("Archive this chat")
        let other = terminalChat("Keep this chat")
        try install([archived, other], in: test.model, selected: archived.id)
        let archivedItem = try XCTUnwrap(test.model.notificationItems.first { $0.conversationID == archived.id })
        XCTAssertTrue(test.model.markNotificationRead(archivedItem.id))
        XCTAssertTrue(test.model.archiveChat(archived.id))
        XCTAssertFalse(test.model.notificationItems.contains { $0.id == archivedItem.id })
        XCTAssertFalse(test.model.openNotification(archivedItem))
        XCTAssertNil(test.model.notificationWindowTarget(archivedItem))
        XCTAssertFalse(test.model.markNotificationRead(archivedItem.id))
        XCTAssertTrue(test.model.notifications.readState.isRead(archivedItem.id))

        XCTAssertTrue(test.model.restoreSidebarConversation(archived.id))
        XCTAssertTrue(test.model.notificationItems.first { $0.id == archivedItem.id }?.isRead == true)
        test.model.deleteConversation(archived.id)
        XCTAssertFalse(test.model.openNotification(archivedItem))
        XCTAssertNil(test.model.notificationWindowTarget(archivedItem))
        XCTAssertTrue(test.model.notifications.readState.isRead(archivedItem.id))

        let stale = try XCTUnwrap(test.model.notificationItems.first { $0.conversationID == other.id })
        let index = try XCTUnwrap(test.model.conversations.firstIndex { $0.id == other.id })
        test.model.conversations[index].messages.removeAll { $0.id == stale.responseID }
        XCTAssertTrue(test.model.saveHistory())
        XCTAssertFalse(test.model.openNotification(stale))
        XCTAssertNil(test.model.notificationWindowTarget(stale))
        XCTAssertFalse(test.model.markNotificationRead(stale.id))
    }

    func testOpeningSameActiveChatKeepsGenerationAndUnsentDraft() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.model.computerWork.automaticRequestRouting = false
        test.send("Hold the current response.")
        try await waitUntil { await test.provider.requests.count == 1 }
        let live = try XCTUnwrap(test.model.notificationItems.first { $0.isLive })
        let generation = test.model.foregroundRun.activeGeneration
        let responseID = test.model.foregroundRun.activeResponse?.messageID
        let selection = test.model.selectedConversationID
        test.model.composer.draft = "Keep this unsent next question."

        XCTAssertTrue(test.model.openNotification(live))
        XCTAssertEqual(test.model.selectedConversationID, selection)
        XCTAssertEqual(test.model.foregroundRun.activeGeneration, generation)
        XCTAssertEqual(test.model.foregroundRun.activeResponse?.messageID, responseID)
        XCTAssertEqual(test.model.composer.draft, "Keep this unsent next question.")
        XCTAssertTrue(test.model.foregroundRun.isGenerating)
        XCTAssertEqual(test.model.notificationWindowTarget(live), selection)
        let cancellations = await test.provider.cancellations
        XCTAssertEqual(cancellations, 0)
        await test.provider.complete(0, answer: "The held response finished.")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
    }

    func testDifferentChatNotificationUsesWindowFallbackWithoutChangingBusyDirtyMainChat() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let target = terminalChat("The notification target")
        var foreground = Conversation(title: "Foreground task", workspacePath: nil)
        foreground.mode = ComposerMode.chat.rawValue
        try install([target, foreground], in: test.model, selected: foreground.id)
        let item = try XCTUnwrap(test.model.notificationItems.first { $0.conversationID == target.id })
        test.model.computerWork.automaticRequestRouting = false
        test.send("Keep the foreground answer running.")
        try await waitUntil { await test.provider.requests.count == 1 }
        let generation = test.model.foregroundRun.activeGeneration
        let responseID = test.model.foregroundRun.activeResponse?.messageID
        test.model.composer.draft = "Unsent foreground guidance"

        XCTAssertFalse(test.model.openNotification(item))
        XCTAssertEqual(test.model.notificationWindowTarget(item), target.id)
        XCTAssertEqual(test.model.selectedConversationID, foreground.id)
        XCTAssertEqual(test.model.foregroundRun.activeGeneration, generation)
        XCTAssertEqual(test.model.foregroundRun.activeResponse?.messageID, responseID)
        XCTAssertEqual(test.model.composer.draft, "Unsent foreground guidance")
        XCTAssertTrue(test.model.foregroundRun.isGenerating)
        XCTAssertTrue(test.model.notifications.readState.isRead(item.id))
        let cancellations = await test.provider.cancellations
        let requests = await test.provider.requests
        XCTAssertEqual(cancellations, 0)
        XCTAssertEqual(requests.count, 1)
        await test.provider.complete(0, answer: "The foreground task finished.")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
    }

    func testFailedReadSaveKeepsUnreadStateAndExplicitReloadAllowsRetry() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let conversation = terminalChat("Persist the read marker")
        try install([conversation], in: test.model, selected: conversation.id)
        let item = try XCTUnwrap(test.model.notificationItems.first)
        let originalReadState = test.model.notifications.readState
        let file = test.model.notifications.readStore.fileURL
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)

        XCTAssertFalse(test.model.markNotificationRead(item.id))
        XCTAssertEqual(test.model.notifications.readState, originalReadState)
        XCTAssertEqual(test.model.unreadNotificationCount, 1)
        XCTAssertNotNil(test.model.notifications.storageError)
        XCTAssertFalse(test.model.notifications.storageWritable)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        try FileManager.default.removeItem(at: file)
        XCTAssertFalse(test.model.markNotificationRead(item.id), "A failed store needs an explicit retry.")
        test.model.reloadNotificationReadState()
        XCTAssertTrue(test.model.notifications.storageWritable)
        XCTAssertNil(test.model.notifications.storageError)
        XCTAssertTrue(test.model.markNotificationRead(item.id))
        XCTAssertEqual(test.model.unreadNotificationCount, 0)
        XCTAssertTrue(try XCTUnwrap(test.model.notifications.readStore.load()).isRead(item.id))
    }

    func testIdleDirtyDifferentChatUsesWindowFallbackWithoutClearingDraft() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let target = terminalChat("Open this transcript")
        let foreground = terminalChat("Keep the composer here")
        try install([target, foreground], in: test.model, selected: foreground.id)
        let item = try XCTUnwrap(test.model.notificationItems.first { $0.conversationID == target.id })
        test.model.composer.draft = "Unsent text while no task is running."
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertFalse(test.model.openNotification(item))
        XCTAssertEqual(test.model.notificationWindowTarget(item), target.id)
        XCTAssertEqual(test.model.selectedConversationID, foreground.id)
        XCTAssertEqual(test.model.composer.draft, "Unsent text while no task is running.")
        XCTAssertNil(test.model.foregroundRun.activeGeneration)
        XCTAssertTrue(test.model.notifications.readState.isRead(item.id))
    }

    func testMarkAllReadsOnlyCurrentItemsAndPreservesExistingMarkersForHiddenChats() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let first = terminalChat("First notification")
        let second = terminalChat("Second notification", state: .failed)
        try install([first, second], in: test.model, selected: first.id)
        let firstItem = try XCTUnwrap(test.model.notificationItems.first { $0.conversationID == first.id })
        XCTAssertTrue(test.model.markNotificationRead(firstItem.id))
        XCTAssertTrue(test.model.archiveChat(first.id))
        XCTAssertEqual(test.model.unreadNotificationCount, 1)

        test.model.markAllNotificationsRead()
        XCTAssertEqual(test.model.unreadNotificationCount, 0)
        XCTAssertTrue(test.model.notifications.readState.isRead(firstItem.id))
        let state = try XCTUnwrap(test.model.notifications.readStore.load())
        XCTAssertEqual(state.readIDs.count, 2)
        XCTAssertTrue(state.isRead(firstItem.id))
    }

    private func terminalChat(
        _ title: String,
        state: ResponseActivity.State = .completed
    ) -> Conversation {
        var activity = ResponseActivity(startedAt: Date().addingTimeInterval(-10))
        activity.finish(state)
        var conversation = Conversation(title: title, workspacePath: nil)
        conversation.mode = ComposerMode.chat.rawValue
        conversation.messages = [
            ChatMessage(role: "user", content: "Explain this task."),
            ChatMessage(role: "assistant", content: "A visible saved result.", activity: activity)
        ]
        return conversation
    }

    private func install(_ conversations: [Conversation], in model: AppModel, selected: UUID) throws {
        model.conversations = conversations
        model.selectedConversationID = selected
        for conversation in conversations { model.registerSidebarConversation(conversation.id) }
        XCTAssertTrue(model.saveHistory())
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The notification fixture did not reach the expected state.")
        throw CancellationError()
    }
}
