import Foundation
import XCTest
@testable import VyronCore

final class VyronAgentEffortCompatibilityTests: XCTestCase {
    func testLegacyAndNewRawValuesEncodeWithoutRenamingSavedChoices() throws {
        let efforts: [AgentEffort] = [.automatic, .quick, .balanced, .deep, .extraHigh, .maximum, .ultra]
        let rawValues = ["auto", "quick", "balanced", "deep", "xhigh", "max", "ultra"]
        XCTAssertEqual(AgentEffort.allCases, efforts)
        for (effort, rawValue) in zip(efforts, rawValues) {
            XCTAssertEqual(effort.rawValue, rawValue)
            let data = Data(("\"" + rawValue + "\"").utf8)
            XCTAssertEqual(try JSONDecoder().decode(AgentEffort.self, from: data), effort)
            XCTAssertEqual(try JSONEncoder().encode(effort), data)
        }
    }

    func testLegacyIntentRouteEffortChoicesStillDecodeAndRoundTrip() throws {
        let expected: [AgentEffort] = [.automatic, .quick, .balanced, .deep]
        for (rawValue, effort) in zip(["auto", "quick", "balanced", "deep"], expected) {
            let literal = "{\"mode\":\"computerTask\",\"goal\":\"Open Safari\",\"effort\":\"" + rawValue + "\"}"
            let route = try JSONDecoder().decode(AssistantRoute.self, from: Data(literal.utf8))
            XCTAssertEqual(route.mode, .computerTask)
            XCTAssertEqual(route.goal, "Open Safari")
            XCTAssertEqual(route.effort, effort)
            let reloaded = try JSONDecoder().decode(AssistantRoute.self, from: JSONEncoder().encode(route))
            XCTAssertEqual(reloaded, route)
        }
    }

    func testScheduledTaskArchiveRoundTripsAllLevelsWithExactManualConnectionAndModel() throws {
        let directory = try directory()
        let store = VyronScheduledTaskStore(fileURL: directory.appendingPathComponent("scheduled-tasks.json"))
        let connectionID = UUID()
        let tasks = AgentEffort.allCases.map { task(effort: $0, connectionID: connectionID) }
        try store.save(tasks)
        let loaded = try store.load()
        XCTAssertEqual(loaded, tasks)
        XCTAssertEqual(loaded.map { $0.definition.context.model.effort }, AgentEffort.allCases)
        XCTAssertTrue(loaded.allSatisfy {
            $0.definition.context.model.connectionID == connectionID
                && $0.definition.context.model.model == "exact-manual-model:q4"
                && !$0.definition.context.model.automaticallySelect
        })
        let archive = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any]
        )
        XCTAssertEqual(archive["version"] as? Int, 1)
        XCTAssertEqual(Set(archive.keys), ["version", "tasks"])
        let encodedTasks = try XCTUnwrap(archive["tasks"] as? [[String: Any]])
        let rawEfforts = try encodedTasks.map { encoded -> String in
            let definition = try XCTUnwrap(encoded["definition"] as? [String: Any])
            let context = try XCTUnwrap(definition["context"] as? [String: Any])
            let model = try XCTUnwrap(context["model"] as? [String: Any])
            return try XCTUnwrap(model["effort"] as? String)
        }
        XCTAssertEqual(rawEfforts, ["auto", "quick", "balanced", "deep", "xhigh", "max", "ultra"])
    }

    func testLegacyTaskCheckpointWithoutEffortFieldPreservesPlanAndReplayEvidence() throws {
        let directory = try directory()
        let id = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let literal = """
            {"schemaVersion":1,"task":{
              "identity":{"id":"11111111-2222-3333-4444-555555555555","projectPath":"/fixture/project",
                "originalGoal":"Finish the original template app.","startedAt":0},
              "plan":[{"title":"Create the project","status":"completed"},
                {"title":"Validate the project","status":"pending"}],
              "progress":{"files":[{"path":"Main.swift",
                "contentHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "status":"saved","recordedAt":3}],
                "checks":[{"command":"swift test","result":{"exitCode":0,"timedOut":false},
                  "summary":"Existing saved validation.","recordedAt":4}],
                "integrations":[{"identity":{"toolName":"mcp_fixture_create",
                  "argumentsHash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
                  "status":"started","summary":"Creation may have completed; verify before retrying.","recordedAt":5}],
                "context":{"guidance":["Keep the original lifecycle."],"decisions":[],"summary":"Saved progress."}},
              "lifecycle":{"status":"failed","updatedAt":10}
            }}
            """
        let file = directory.appendingPathComponent(id.uuidString + ".json")
        try Data(literal.utf8).write(to: file)
        let store = try VyronDevelopmentTaskStore(directoryURL: directory, projectPath: "/fixture/project")
        let loaded = try XCTUnwrap(store.load(id: id))
        XCTAssertEqual(loaded.identity.originalGoal, "Finish the original template app.")
        XCTAssertEqual(loaded.plan.map(\.status), [.completed, .pending])
        XCTAssertEqual(loaded.progress.files.map(\.path), ["Main.swift"])
        XCTAssertEqual(loaded.progress.checks.first?.command, "swift test")
        XCTAssertEqual(loaded.progress.integrations.first?.status, .started)
        XCTAssertEqual(loaded.guidance, ["Keep the original lifecycle."])
        try store.save(loaded)
        XCTAssertEqual(try store.load(id: id), loaded)
        let archive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(archive["schemaVersion"] as? Int, 1)
        let task = try XCTUnwrap(archive["task"] as? [String: Any])
        XCTAssertNil(task["effort"])
        XCTAssertEqual(Set(task.keys), ["identity", "plan", "progress", "lifecycle"])
    }

    private func task(effort: AgentEffort, connectionID: UUID) -> VyronScheduledTask {
        let model = VyronScheduledModelSelection(
            connectionID: connectionID, model: "exact-manual-model:q4", automaticallySelect: false, effort: effort
        )
        let context = VyronScheduledTaskContext(
            workspacePath: "/fixture/project", mode: .agent, model: model, projectPath: "/fixture/project"
        )
        let date = Date(timeIntervalSince1970: 2_000_000_000)
        return VyronScheduledTask(
            id: UUID(),
            definition: VyronScheduledTaskDefinition(
                title: "Saved task", prompt: "Review the project.", context: context
            ),
            schedule: VyronTaskSchedule(startsAt: date, recurrence: .once, timeZoneIdentifier: "UTC"),
            progress: VyronScheduledTaskProgress(isEnabled: true, nextRunAt: date, lastRun: nil)
        )
    }

    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("VyronEffortCompatibility-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }
}
