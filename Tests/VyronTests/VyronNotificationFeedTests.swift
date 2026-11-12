import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronNotificationFeedTests: XCTestCase {
    func testFirstShowTerminalEventsAreUnreadAndIdentityRemainsStable() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var conversation = Conversation(title: "Template app", workspacePath: "/fixture/source")
        conversation.projectPath = "/fixture/project"
        let completed = message(.completed, at: now, content: "The visible result is ready.")
        let failed = message(.failed, at: now.addingTimeInterval(-10), content: "A visible failure explanation.")
        conversation.messages = [
            ChatMessage(role: "user", content: "A user message is not an event."), completed, failed
        ]
        let first = build([conversation], now: now)
        let repeated = build([conversation], now: now.addingTimeInterval(60))
        XCTAssertEqual(first.map(\.id), [.priority])
        XCTAssertEqual(first.flatMap(\.items).map(\.id), repeated.flatMap(\.items).map(\.id))
        XCTAssertEqual(first.flatMap(\.items).map(\.responseID), [completed.id, failed.id])
        XCTAssertEqual(first.flatMap(\.items).map(\.date), [now, now.addingTimeInterval(-10)])
        XCTAssertTrue(first.flatMap(\.items).allSatisfy(\.isUnread))
        XCTAssertEqual(first.first?.items.first?.content.projectPath, conversation.projectPath)
        XCTAssertEqual(first.first?.items.first?.content.preview, completed.content)
    }

    func testStaleWorkingStoppedAndLegacyHistoryDoNotProduceNotifications() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var conversation = Conversation(title: "Old history", workspacePath: nil)
        var noFinish = try XCTUnwrap(message(.completed, at: now).activity)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(noFinish)) as? [String: Any])
        json.removeValue(forKey: "finishedAt")
        noFinish = try JSONDecoder().decode(ResponseActivity.self, from: JSONSerialization.data(withJSONObject: json))
        conversation.messages = [
            ChatMessage(role: "assistant", content: "Legacy without activity"),
            message(.working, at: now),
            message(.stopped, at: now),
            ChatMessage(role: "assistant", content: "Legacy without a finished date", activity: noFinish)
        ]
        XCTAssertTrue(build([conversation], now: now).isEmpty)
        let stopped = try XCTUnwrap(conversation.messages.first { $0.activity?.state == .stopped })
        let runtime = VyronNotificationRuntime(liveResponses: [
            VyronNotificationResponseID(conversationID: conversation.id, responseID: stopped.id)
        ])
        XCTAssertTrue(build([conversation], runtime: runtime, now: now).isEmpty)
    }

    func testOnlyExactLiveResponseIsShownAndAttentionReplacesItsWorkingCard() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var first = Conversation(title: "First project", workspacePath: nil)
        var second = Conversation(title: "Other project", workspacePath: nil)
        first.messages = [message(.working, at: now)]
        second.messages = [message(.working, at: now)]
        let response = VyronNotificationResponseID(conversationID: first.id, responseID: first.messages[0].id)
        let request = UUID()
        let attention = VyronNotificationAttention(
            target: .response(response), attentionID: request,
            content: VyronNotificationContent(title: "Needs your answer", preview: "Choose a color.", projectPath: nil),
            date: now
        )
        var runtime = VyronNotificationRuntime(liveResponses: [response])
        let live = try XCTUnwrap(build([first, second], runtime: runtime, now: now).first?.items.first)
        XCTAssertTrue(live.isLive)
        XCTAssertFalse(live.isUnread)
        XCTAssertEqual(live.conversationID, first.id)
        runtime.attention = [attention, attention]
        let items = build([first, second], runtime: runtime, now: now).flatMap(\.items)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, attention.id)
        XCTAssertTrue(items.first?.isUnread == true)
        var read = VyronNotificationReadState()
        try read.markRead(attention.id)
        let readAttention = build([first, second], runtime: runtime, read: read, now: now).flatMap(\.items)
        XCTAssertEqual(readAttention.count, 1)
        XCTAssertTrue(readAttention.first?.isPriority == true)
        XCTAssertFalse(readAttention.first?.isUnread == true)
        runtime.liveResponses = []
        XCTAssertTrue(build([first, second], runtime: runtime, now: now).isEmpty)
    }

    func testReadingLiveResponseNeverMarksItsLaterCompletionRead() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var conversation = Conversation(title: "A task", workspacePath: nil)
        conversation.messages = [message(.working, at: now)]
        let response = VyronNotificationResponseID(
            conversationID: conversation.id, responseID: conversation.messages[0].id
        )
        let runtime = VyronNotificationRuntime(liveResponses: [response])
        let live = try XCTUnwrap(build([conversation], runtime: runtime, now: now).first?.items.first)
        var read = VyronNotificationReadState()
        try read.markRead(live.id)
        conversation.messages[0].activity?.finish(.completed, at: now.addingTimeInterval(20))
        let completed = try XCTUnwrap(build([conversation], read: read, now: now).first?.items.first)
        XCTAssertNotEqual(completed.id, live.id)
        XCTAssertEqual(completed.kind, .completed)
        XCTAssertTrue(completed.isUnread)
    }

    func testReadTerminalGroupingHonorsCalendarDayBoundariesInsteadOfElapsedHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 3 * 3_600))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-04T21:30:00Z"))
        let dates = [now, now.addingTimeInterval(-3_600), now.addingTimeInterval(-49 * 3_600)]
        var conversation = Conversation(title: "Daily tasks", workspacePath: nil)
        conversation.messages = dates.map { message(.completed, at: $0) }
        var read = VyronNotificationReadState()
        for message in conversation.messages {
            try read.markRead(VyronNotificationID(
                target: .response(VyronNotificationResponseID(conversationID: conversation.id, responseID: message.id)),
                kind: .completed
            ))
        }
        let groups = VyronNotificationFeed.build(
            conversations: [conversation], runtime: VyronNotificationRuntime(), readState: read,
            calendarContext: VyronNotificationCalendarContext(now: now, calendar: calendar)
        )
        XCTAssertEqual(groups.map(\.id), [.today, .yesterday, .earlier])
        XCTAssertEqual(groups.flatMap(\.items).map(\.date), dates)
    }

    func testPreviewNeverIncludesInternalActivityContextOrOtherRoles() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var conversation = Conversation(title: "Visible task", workspacePath: nil)
        var response = message(.working, at: now, content: String(repeating: "Visible text ", count: 100))
        response.activity?.record("PRIVATE_ACTIVITY", detail: "PRIVATE_TOOL_ARGUMENTS")
        response.activity?.finish(.completed, at: now)
        conversation.messages = [response, ChatMessage(role: "tool", content: "PRIVATE_TOOL_CONTENT")]
        conversation.contextByMessageID = [response.id.uuidString: "PRIVATE_CONTEXT"]
        let item = build([conversation], now: now).first?.items.first
        XCTAssertEqual(item?.content.preview.count, VyronNotificationLimits.previewCharacters)
        XCTAssertFalse(item?.content.preview.contains("PRIVATE") == true)
    }

    func testScheduledOnlyAndPluginTargetsStayDistinctWithoutFabricatedConversationIDs() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let run = VyronNotificationScheduledRunID(taskID: UUID(), runID: UUID())
        let scheduledID = VyronNotificationID(target: .scheduledRun(run), kind: .failed)
        let scheduled = VyronNotificationItem(
            id: scheduledID,
            content: VyronNotificationContent(
                title: "Scheduled task", preview: "No model was available.", projectPath: nil
            ),
            date: now, isRead: true
        )
        let plugin = VyronNotificationAttention(
            target: .plugins, attentionID: UUID(),
            content: VyronNotificationContent(
                title: "Plugin needs review", preview: "Review the connection.", projectPath: nil
            ),
            date: now.addingTimeInterval(10)
        )
        let runtime = VyronNotificationRuntime(attention: [plugin], scheduledItems: [scheduled, scheduled])
        let groups = build([], runtime: runtime, now: now)
        let items = groups.flatMap(\.items)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.id), [plugin.id, scheduledID])
        XCTAssertTrue(items.allSatisfy { $0.conversationID == nil && $0.responseID == nil })
        XCTAssertTrue(items.allSatisfy(\.isUnread))
        var read = VyronNotificationReadState()
        try read.markRead(scheduledID)
        let readGroups = build([], runtime: runtime, read: read, now: now)
        XCTAssertEqual(readGroups.map(\.id), [.priority, .today])
        XCTAssertEqual(readGroups.last?.items.first?.id, scheduledID)
    }

    private func message(
        _ state: ResponseActivity.State,
        at date: Date,
        content: String = "Visible task result."
    ) -> ChatMessage {
        var activity = ResponseActivity(startedAt: date.addingTimeInterval(-20))
        if state != .working { activity.finish(state, at: date) }
        return ChatMessage(role: "assistant", content: content, activity: activity)
    }

    private func build(
        _ conversations: [Conversation],
        runtime: VyronNotificationRuntime = VyronNotificationRuntime(),
        read: VyronNotificationReadState = .empty,
        now: Date
    ) -> [VyronNotificationGroup] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return VyronNotificationFeed.build(
            conversations: conversations, runtime: runtime, readState: read,
            calendarContext: VyronNotificationCalendarContext(now: now, calendar: calendar)
        )
    }
}
