import Foundation
import XCTest
@testable import VyronCore

final class VyronActivityTrackingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testLegacyFlatActivityDecodesAndKeepsItsOriginalWireKeys() throws {
        let id = UUID()
        let json = """
        {"startedAt":0,"state":"working","entries":[
        {"id":"\(id)","date":2,"kind":"tool","title":"Reading notes","detail":"README.md"}
        ]}
        """
        let activity = try JSONDecoder().decode(ResponseActivity.self, from: Data(json.utf8))
        XCTAssertEqual(activity.entries.first?.id, id)
        XCTAssertEqual(activity.entries.first?.detail, "README.md")
        XCTAssertNil(activity.entries.first?.category)
        XCTAssertNil(activity.subagents)
        XCTAssertTrue(activity.subagentActivities.isEmpty)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(activity)) as? [String: Any]
        )
        let entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        XCTAssertEqual(Set(entries[0].keys), ["id", "date", "kind", "title", "detail"])
        XCTAssertNil(entries[0]["content"])
    }

    func testCategoriesAndWorkerResultsSurviveHistoryRoundTrip() throws {
        var activity = ResponseActivity(startedAt: start)
        activity.record(VyronActivityContent(
            kind: .tool, title: "Reading notes", detail: "README.md", category: .read
        ), at: start)
        let worker = identity("Read source")
        activity.recordSubagent(.init(identity: worker, update: .started, date: start.addingTimeInterval(1)))
        activity.recordSubagent(.init(
            identity: worker,
            update: .activity(DevelopmentEvent(kind: .toolStarted, message: "Reading code", tool: "read_file")),
            date: start.addingTimeInterval(2)
        ))
        activity.recordSubagent(.init(
            identity: worker,
            update: .finished(VyronSubagentCompletion(state: .completed, summary: "The model owns the state.")),
            date: start.addingTimeInterval(4)
        ))
        activity.finish(.completed, at: start.addingTimeInterval(5))
        let decoded = try JSONDecoder().decode(ResponseActivity.self, from: JSONEncoder().encode(activity))
        XCTAssertEqual(decoded, activity)
        XCTAssertEqual(decoded.entries.first?.category, .read)
        XCTAssertEqual(decoded.subagentActivities.first?.identity.model, "fixture-coder")
        XCTAssertEqual(decoded.subagentActivities.first?.activity.state, .completed)
        XCTAssertEqual(decoded.subagentActivities.first?.activity.entries.first?.category, .read)
        XCTAssertEqual(decoded.subagentActivities.first?.summary, "The model owns the state.")
    }

    func testParentFinishStopsOnlyPendingWorkersAndRejectsLateUpdates() {
        var activity = ResponseActivity(startedAt: start)
        let finished = identity("Finished")
        let pending = identity("Still reading")
        for worker in [finished, pending] {
            activity.recordSubagent(.init(identity: worker, update: .started, date: start))
        }
        activity.recordSubagent(.init(
            identity: finished,
            update: .finished(VyronSubagentCompletion(state: .failed, summary: "The notes were unavailable.")),
            date: start.addingTimeInterval(3)
        ))
        activity.recordSubagent(.init(
            identity: pending,
            update: .activity(DevelopmentEvent(kind: .status, message: "Inspecting files")),
            date: start.addingTimeInterval(8)
        ))
        activity.finish(.stopped, at: start.addingTimeInterval(2))
        XCTAssertEqual(activity.finishedAt, start.addingTimeInterval(8))
        XCTAssertEqual(activity.subagentActivities.map { $0.activity.state }, [.failed, .stopped])
        XCTAssertEqual(activity.subagentActivities.first?.summary, "The notes were unavailable.")
        let stopped = activity
        activity.recordSubagent(.init(
            identity: pending,
            update: .finished(VyronSubagentCompletion(state: .completed, summary: "A late response")),
            date: start.addingTimeInterval(10)
        ))
        XCTAssertEqual(activity, stopped)
    }

    func testWorkerIdentityAndRetentionAreBoundedWithoutRestartingFinishedWorkers() {
        var activity = ResponseActivity(startedAt: start)
        let worker = identity("Review")
        activity.recordSubagent(.init(identity: worker, update: .started, date: start))
        activity.recordSubagent(.init(
            identity: worker,
            update: .finished(VyronSubagentCompletion(state: .completed, summary: String(repeating: "s", count: 6_100))),
            date: start.addingTimeInterval(1)
        ))
        activity.recordSubagent(.init(identity: worker, update: .started, date: start.addingTimeInterval(2)))
        for index in 0..<5 {
            activity.recordSubagent(.init(identity: identity("Helper \(index)"), update: .started, date: start))
        }
        XCTAssertEqual(activity.subagentActivities.count, 3)
        XCTAssertEqual(activity.subagentActivities.first?.activity.state, .completed)
        XCTAssertEqual(activity.subagentActivities.first?.summary?.count, 6_000)
    }

    func testSuccessfulFileOutputAndCommandStreamsStayOutOfTrackedHistory() {
        let output = "PRIVATE_FILE_OUTPUT"
        let success = DevelopmentEvent(
            kind: .toolFinished, message: "Tool completed", tool: "read_file", content: output
        )
        XCTAssertNil(success.activityContent?.detail)
        XCTAssertEqual(success.activityContent?.category, .read)
        XCTAssertNil(DevelopmentEvent(kind: .commandOutput, message: "Output", content: output).activityContent)
        let failure = DevelopmentEvent(
            kind: .toolFinished, message: "Tool failed", tool: "read_file", content: output, failure: "Missing file"
        )
        XCTAssertEqual(failure.activityContent?.detail, "Missing file")
        XCTAssertEqual(DevelopmentEvent(kind: .toolStarted, message: "Inspecting", tool: "mcp_tool").activityCategory,
                       .integration)
    }

    private func identity(_ name: String) -> VyronSubagentIdentity {
        VyronSubagentIdentity(name: name, prompt: "Inspect the existing source.", model: "fixture-coder")
    }
}
