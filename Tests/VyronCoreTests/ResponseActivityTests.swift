import Foundation
import XCTest
@testable import VyronCore

final class ResponseActivityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testExistingChatHistoryDecodesWithoutActivity() throws {
        let id = UUID()
        let data = Data("{\"id\":\"\(id.uuidString)\",\"role\":\"assistant\",\"content\":\"An older answer\"}".utf8)
        let message = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(message.id, id)
        XCTAssertEqual(message.content, "An older answer")
        XCTAssertNil(message.activity)
    }

    func testCompletedActivitySurvivesMessageHistoryRoundTrip() throws {
        var activity = ResponseActivity(startedAt: start)
        activity.record("Reading Sources/Main.swift", detail: "Sources/Main.swift", kind: .tool, at: start.addingTimeInterval(2))
        activity.record("The entry point creates the main window.", kind: .explanation, at: start.addingTimeInterval(3))
        activity.finish(.completed, at: start.addingTimeInterval(8))
        let history = [
            ChatMessage(role: "user", content: "Explain this project"),
            ChatMessage(role: "assistant", content: "Here is the project overview.", activity: activity)
        ]
        let decoded = try JSONDecoder().decode([ChatMessage].self, from: JSONEncoder().encode(history))
        XCTAssertEqual(decoded, history)
        XCTAssertEqual(decoded.last?.activity?.state, .completed)
        XCTAssertEqual(decoded.last?.activity?.entries.count, 2)
        XCTAssertEqual(decoded.last?.activity?.elapsed(at: start.addingTimeInterval(100)), 8)
    }

    func testRecordsRetainNewestBoundedEntriesAndBoundTheirText() {
        var activity = ResponseActivity(startedAt: start)
        for index in 0..<125 {
            activity.record("Step \(index)", at: start.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(activity.entries.count, 120)
        XCTAssertEqual(activity.entries.first?.title, "Step 5")
        XCTAssertEqual(activity.entries.last?.title, "Step 124")
        XCTAssertEqual(Set(activity.entries.map(\.id)).count, 120)

        activity.record(String(repeating: "a", count: 2_100), detail: String(repeating: "b", count: 6_100))
        XCTAssertEqual(activity.entries.last?.title.count, 2_000)
        XCTAssertEqual(activity.entries.last?.detail?.count, 6_000)
        XCTAssertEqual(activity.entries.count, 120)
    }

    func testBlankAndAdjacentDuplicateRecordsAreIgnored() {
        var activity = ResponseActivity(startedAt: start)
        activity.record(" \n\t ")
        activity.record(" Preparing context ", detail: " \n ", at: start)
        activity.record("Preparing context", at: start.addingTimeInterval(1))
        XCTAssertEqual(activity.entries.count, 1)
        XCTAssertEqual(activity.entries.first?.title, "Preparing context")
        XCTAssertNil(activity.entries.first?.detail)

        activity.record("Preparing context", kind: .explanation, at: start.addingTimeInterval(2))
        XCTAssertEqual(activity.entries.count, 2)
    }

    func testTerminalStatesRejectLateEventsAndCannotBeReopenedOrOverwritten() {
        for state in [ResponseActivity.State.completed, .stopped, .failed] {
            var activity = ResponseActivity(startedAt: start)
            activity.record("Considering the next step", at: start.addingTimeInterval(1))
            activity.finish(.working, at: start.addingTimeInterval(2))
            XCTAssertEqual(activity.state, .working)
            XCTAssertNil(activity.finishedAt)
            activity.finish(state, at: start.addingTimeInterval(3))
            let finished = activity
            activity.record("Late event", at: start.addingTimeInterval(4))
            activity.finish(.working, at: start.addingTimeInterval(5))
            activity.finish(.completed, at: start.addingTimeInterval(6))
            XCTAssertEqual(activity, finished)
            XCTAssertEqual(activity.elapsed(at: start.addingTimeInterval(100)), 3)
        }
    }

    func testClockChangesDoNotProduceNegativeOrReversedTimes() {
        var activity = ResponseActivity(startedAt: start)
        XCTAssertEqual(activity.elapsed(at: start.addingTimeInterval(-1)), 0)
        activity.record("Starting", at: start.addingTimeInterval(-5))
        activity.record("Reading", at: start.addingTimeInterval(10))
        activity.record("Responding", at: start.addingTimeInterval(4))
        activity.finish(.stopped, at: start.addingTimeInterval(2))
        XCTAssertEqual(activity.entries.map(\.date), [start, start.addingTimeInterval(10), start.addingTimeInterval(10)])
        XCTAssertEqual(activity.finishedAt, start.addingTimeInterval(10))
        XCTAssertEqual(activity.elapsed(), 10)
    }
}
