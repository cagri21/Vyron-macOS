import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronActivityTrackingStateTests: XCTestCase {
    private var directory: URL!
    private var model: AppModel!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        model = AppModel(historyDirectory: directory)
        var conversation = Conversation(title: "Tracked task", workspacePath: nil)
        let answer = ChatMessage(role: "assistant", content: "", activity: ResponseActivity())
        conversation.messages = [ChatMessage(role: "user", content: "Inspect the project"), answer]
        model.conversations = [conversation]
        model.selectedConversationID = conversation.id
    }

    override func tearDown() async throws {
        model.stopGeneration()
        model = nil
        try FileManager.default.removeItem(at: directory)
        directory = nil
    }

    func testWorkerSelectionAndResultsPersistWithTheOwningResponse() throws {
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        let messageID = try XCTUnwrap(model.messages.last?.id)
        let worker = VyronSubagentIdentity(name: "Source review", prompt: "Read the source.", model: "actual-model")
        model.recordSubagentEvent(.init(identity: worker, update: .started),
                                 conversationID: conversationID, messageID: messageID)
        model.appNavigation.showWorkspace = true
        model.openActivity(conversationID: conversationID, messageID: messageID, subagentID: worker.id)
        XCTAssertFalse(model.appNavigation.showWorkspace)
        XCTAssertEqual(model.trackedMessage?.id, messageID)
        XCTAssertEqual(model.trackedSubagent?.identity.model, "actual-model")
        model.recordSubagentEvent(.init(
            identity: worker,
            update: .finished(VyronSubagentCompletion(state: .completed, summary: "The view forwards actions."))
        ), conversationID: conversationID, messageID: messageID)
        XCTAssertEqual(model.trackedActivity?.state, .completed)
        let reopened = AppModel(historyDirectory: directory)
        let saved = try XCTUnwrap(reopened.conversations.first?.messages.last?.activity?.subagentActivities.first)
        XCTAssertEqual(saved.identity, worker)
        XCTAssertEqual(saved.summary, "The view forwards actions.")
        XCTAssertEqual(saved.activity.state, .completed)
    }

    func testSwitchingChatAndOpeningFilesClearTrackingSelection() throws {
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        let messageID = try XCTUnwrap(model.messages.last?.id)
        model.openActivity(conversationID: conversationID, messageID: messageID)
        XCTAssertNotNil(model.trackedActivity)
        model.appNavigation.showWorkspace = true
        XCTAssertNil(model.appNavigation.trackingSelection)
        model.openActivity(conversationID: conversationID, messageID: messageID)
        let other = Conversation(title: "Other chat", workspacePath: nil)
        model.conversations.append(other)
        model.selectConversation(other.id)
        XCTAssertNil(model.appNavigation.trackingSelection)
        model.openActivity(conversationID: conversationID, messageID: messageID)
        XCTAssertNil(model.appNavigation.trackingSelection)
    }

    func testOpeningToolEntryTargetsItsOwningResponse() throws {
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        let messageID = try XCTUnwrap(model.messages.last?.id)
        model.conversations[0].messages[1].activity?.record("Reading source", detail: "App.swift", kind: .tool)
        let entryID = try XCTUnwrap(model.messages.last?.activity?.entries.last?.id)
        model.appNavigation.showWorkspace = true

        model.openActivity(conversationID: conversationID, messageID: messageID, entryID: entryID)

        XCTAssertFalse(model.appNavigation.showWorkspace)
        XCTAssertEqual(model.appNavigation.trackingSelection?.conversationID, conversationID)
        XCTAssertEqual(model.appNavigation.trackingSelection?.messageID, messageID)
        XCTAssertEqual(model.appNavigation.trackingSelection?.entryID, entryID)
        XCTAssertNil(model.appNavigation.trackingSelection?.subagentID)
        XCTAssertEqual(model.trackedMessage?.id, messageID)
        XCTAssertEqual(model.trackedActivity?.entries.last?.id, entryID)
        XCTAssertNil(model.trackedSubagent)
    }

    func testUnknownEntryDoesNotReplaceAnExistingTrackingSelection() throws {
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        let messageID = try XCTUnwrap(model.messages.last?.id)
        model.conversations[0].messages[1].activity?.record("Reading source", kind: .tool)
        let entryID = try XCTUnwrap(model.messages.last?.activity?.entries.last?.id)
        model.openActivity(conversationID: conversationID, messageID: messageID, entryID: entryID)
        let selection = model.appNavigation.trackingSelection

        model.openActivity(conversationID: conversationID, messageID: messageID, entryID: UUID())

        XCTAssertEqual(model.appNavigation.trackingSelection, selection)
        XCTAssertEqual(model.trackedMessage?.id, messageID)
    }

    func testEntrySelectionCannotCrossParentAndWorkerActivities() throws {
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        let messageID = try XCTUnwrap(model.messages.last?.id)
        model.conversations[0].messages[1].activity?.record("Reading parent source", kind: .tool)
        let parentEntryID = try XCTUnwrap(model.messages.last?.activity?.entries.last?.id)
        let worker = VyronSubagentIdentity(name: "Review", prompt: "Inspect files.", model: "fixture")
        model.recordSubagentEvent(.init(identity: worker, update: .started),
                                 conversationID: conversationID, messageID: messageID)
        model.recordSubagentEvent(.init(
            identity: worker,
            update: .activity(DevelopmentEvent(kind: .status, message: "Reading worker source"))
        ), conversationID: conversationID, messageID: messageID)
        let workerEntryID = try XCTUnwrap(
            model.messages.last?.activity?.subagentActivities.first?.activity.entries.last?.id
        )
        model.openActivity(conversationID: conversationID, messageID: messageID, entryID: parentEntryID)
        let parentSelection = model.appNavigation.trackingSelection

        model.openActivity(
            conversationID: conversationID, messageID: messageID, subagentID: worker.id, entryID: parentEntryID
        )
        XCTAssertEqual(model.appNavigation.trackingSelection, parentSelection)
        model.openActivity(conversationID: conversationID, messageID: messageID, entryID: workerEntryID)
        XCTAssertEqual(model.appNavigation.trackingSelection, parentSelection)

        model.openActivity(
            conversationID: conversationID, messageID: messageID, subagentID: worker.id, entryID: workerEntryID
        )
        XCTAssertEqual(model.appNavigation.trackingSelection?.conversationID, conversationID)
        XCTAssertEqual(model.appNavigation.trackingSelection?.messageID, messageID)
        XCTAssertEqual(model.appNavigation.trackingSelection?.subagentID, worker.id)
        XCTAssertEqual(model.appNavigation.trackingSelection?.entryID, workerEntryID)
        XCTAssertEqual(model.trackedSubagent?.id, worker.id)
        XCTAssertEqual(model.trackedActivity?.entries.last?.id, workerEntryID)
    }

    func testRepeatedToolClickRequestsAFreshRevealForTheSameEntry() throws {
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        let messageID = try XCTUnwrap(model.messages.last?.id)
        model.conversations[0].messages[1].activity?.record("Reading source", kind: .tool)
        let entryID = try XCTUnwrap(model.messages.last?.activity?.entries.last?.id)
        model.openActivity(conversationID: conversationID, messageID: messageID, entryID: entryID)
        let firstReveal = model.appNavigation.trackingSelection?.revealID

        model.openActivity(conversationID: conversationID, messageID: messageID, entryID: entryID)

        XCTAssertNotEqual(model.appNavigation.trackingSelection?.revealID, firstReveal)
        XCTAssertEqual(model.appNavigation.trackingSelection?.entryID, entryID)
        XCTAssertEqual(model.trackedMessage?.id, messageID)
    }

    func testDirectEntryCannotOpenAfterSwitchingToAnotherChat() throws {
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        let messageID = try XCTUnwrap(model.messages.last?.id)
        model.conversations[0].messages[1].activity?.record("Reading source", kind: .tool)
        let entryID = try XCTUnwrap(model.messages.last?.activity?.entries.last?.id)
        let other = Conversation(title: "Other chat", workspacePath: nil)
        model.conversations.append(other)
        model.selectConversation(other.id)

        model.openActivity(conversationID: conversationID, messageID: messageID, entryID: entryID)

        XCTAssertNil(model.appNavigation.trackingSelection)
        XCTAssertNil(model.trackedMessage)
    }

    func testLateWorkerUpdatesCannotChangeAStoppedResponse() throws {
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        let messageID = try XCTUnwrap(model.messages.last?.id)
        let worker = VyronSubagentIdentity(name: "Review", prompt: "Inspect files.", model: "fixture")
        model.recordSubagentEvent(.init(identity: worker, update: .started),
                                 conversationID: conversationID, messageID: messageID)
        model.conversations[0].messages[1].activity?.finish(.stopped)
        let stopped = model.messages.last?.activity
        model.recordSubagentEvent(.init(
            identity: worker,
            update: .finished(VyronSubagentCompletion(state: .completed, summary: "Late completion"))
        ), conversationID: conversationID, messageID: messageID)
        XCTAssertEqual(model.messages.last?.activity, stopped)
    }

    func testReopenStopsPendingWorkersAtTheirLatestRecordedTime() throws {
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        let messageID = try XCTUnwrap(model.messages.last?.id)
        let worker = VyronSubagentIdentity(name: "Review", prompt: "Inspect files.", model: "fixture")
        let later = try XCTUnwrap(model.messages.last?.activity?.startedAt).addingTimeInterval(8)
        model.recordSubagentEvent(.init(identity: worker, update: .started),
                                 conversationID: conversationID, messageID: messageID)
        model.recordSubagentEvent(.init(
            identity: worker,
            update: .activity(DevelopmentEvent(kind: .status, message: "Reading source")), date: later
        ), conversationID: conversationID, messageID: messageID)
        let reopened = AppModel(historyDirectory: directory)
        let activity = try XCTUnwrap(reopened.conversations.first?.messages.last?.activity)
        XCTAssertEqual(activity.state, .stopped)
        XCTAssertEqual(activity.finishedAt, later)
        XCTAssertEqual(activity.subagentActivities.first?.activity.state, .stopped)
        XCTAssertEqual(activity.subagentActivities.first?.activity.finishedAt, later)
    }
}
