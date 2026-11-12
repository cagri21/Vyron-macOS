import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

final class VyronDevelopmentTaskStateTests: XCTestCase {
    private let projectPath = "/Projects/Fixture"

    func testCheckpointRoundTripRetainsFullGoalPlanEvidenceAndUserGuidance() throws {
        let store = try store()
        let goal = "Create an application. " + String(repeating: "Full request detail. ", count: 1_000)
        var state = task(goal: goal)
        try state.updatePlan(VyronDevelopmentPlanUpdate(steps: [
            VyronDevelopmentPlanStep(title: "Inspect project", status: .completed),
            VyronDevelopmentPlanStep(title: "Implement screens", status: .inProgress),
            VyronDevelopmentPlanStep(title: "Verify application")
        ], explanation: "Keep the existing architecture."))
        try state.recordGuidance("Preserve the existing navigation and all user edits.")
        try state.recordFile(VyronDevelopmentFileProgress(
            path: "Sources/App.swift", contentHash: VyronDevelopmentFileProgress.hash(content: "let value = 1\n")
        ))
        try state.recordCheck(VyronDevelopmentCheckProgress(
            command: "swift test", result: VyronDevelopmentCheckResult(exitCode: 1, timedOut: false),
            summary: "A regression remains."
        ))
        try state.recordIntegration(VyronDevelopmentIntegrationProgress(
            identity: VyronDevelopmentIntegrationIdentity(
                toolName: "design_export", argumentsHash: VyronDevelopmentFileProgress.hash(content: "selected design")
            ), status: .succeeded, summary: "Exported the selected design once."
        ))
        state.updateSummary("The first screen is implemented; fix the failing regression next.")
        state.finish(.interrupted, detail: "Application closed.")

        try store.save(state)
        let restored = try XCTUnwrap(store.load(id: state.identity.id))

        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.identity.originalGoal, goal)
        XCTAssertEqual(restored.guidance, ["Preserve the existing navigation and all user edits."])
        XCTAssertEqual(restored.status, .interrupted)
        XCTAssertFalse(restored.progress.checks[0].result.succeeded)
        XCTAssertEqual(restored.progress.integrations.count, 1)
        XCTAssertLessThan(restored.compactSummary().utf8.count, goal.utf8.count)
    }

    func testLatestUnfinishedIsScopedToProvidedChatDirectoryAndExactGoal() throws {
        let directory = try directory()
        let firstChat = try VyronDevelopmentTaskStore(
            directoryURL: directory.appendingPathComponent("first-chat"), projectPath: projectPath
        )
        let secondChat = try VyronDevelopmentTaskStore(
            directoryURL: directory.appendingPathComponent("second-chat"), projectPath: projectPath
        )
        var interrupted = task(goal: "Build the app")
        interrupted.finish(.interrupted)
        var completed = task(goal: "Different task")
        completed.finish(.completed)
        let unrelated = task(goal: "Build the app")
        try firstChat.save(interrupted)
        try firstChat.save(completed)
        try secondChat.save(unrelated)

        XCTAssertEqual(try firstChat.latestUnfinished()?.identity.id, interrupted.identity.id)
        XCTAssertEqual(try firstChat.latestUnfinished(goal: "Build the app")?.identity.id, interrupted.identity.id)
        XCTAssertNil(try firstChat.latestUnfinished(goal: "Other wording"))
        XCTAssertEqual(try secondChat.latestUnfinished()?.identity.id, unrelated.identity.id)
    }

    func testCorruptCheckpointCannotBeOverwrittenAndOtherJournalIsUnchanged() throws {
        let store = try store()
        let state = task()
        try store.save(state)
        let journal = store.directoryURL.appendingPathComponent("changes.json")
        let journalData = Data("Existing workspace journal".utf8)
        try journalData.write(to: journal)
        let checkpoint = store.directoryURL.appendingPathComponent(state.identity.id.uuidString + ".json")
        let damaged = Data("{ incomplete task".utf8)
        try damaged.write(to: checkpoint)

        XCTAssertThrowsError(try store.load(id: state.identity.id))
        XCTAssertThrowsError(try store.save(state))
        XCTAssertEqual(try Data(contentsOf: checkpoint), damaged)
        XCTAssertEqual(try Data(contentsOf: journal), journalData)
    }

    func testCheckpointRejectsWrongProjectAndSymlinkedRecordsOrDirectory() throws {
        let root = try directory()
        let store = try VyronDevelopmentTaskStore(directoryURL: root, projectPath: projectPath)
        let state = task()
        try store.save(state)
        let otherProject = try VyronDevelopmentTaskStore(directoryURL: root, projectPath: "/Projects/Other")
        XCTAssertThrowsError(try otherProject.load(id: state.identity.id))

        let external = root.appendingPathComponent("preserved.txt")
        let original = Data("Preserve me".utf8)
        try original.write(to: external)
        let another = task()
        let link = root.appendingPathComponent(another.identity.id.uuidString + ".json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        XCTAssertThrowsError(try store.save(another))
        XCTAssertEqual(try Data(contentsOf: external), original)

        let directoryLink = root.appendingPathComponent("linked-history")
        try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: root)
        let linked = try VyronDevelopmentTaskStore(directoryURL: directoryLink, projectPath: projectPath)
        XCTAssertThrowsError(try linked.load(id: state.identity.id))
    }

    func testPlanToolDecodesStagesAndRejectsAmbiguousOrOversizedUpdates() throws {
        let call = planCall([
            ["step": .string("Inspect project"), "status": .string("completed")],
            ["step": .string("Implement screens"), "status": .string("in_progress")],
            ["step": .string("Verify"), "status": .string("pending")]
        ])
        let update = try VyronDevelopmentPlanTool.decode(call)
        XCTAssertEqual(update.steps.map(\.status), [.completed, .inProgress, .pending])
        XCTAssertEqual(VyronDevelopmentPlanToolSchema.definition.name, "update_plan")

        let duplicate = ["step": DevelopmentJSONValue.string("Same"), "status": .string("pending")]
        XCTAssertThrowsError(try VyronDevelopmentPlanTool.decode(planCall([duplicate, duplicate])))
        let active = ["step": DevelopmentJSONValue.string("First"), "status": .string("in_progress")]
        let otherActive = ["step": DevelopmentJSONValue.string("Second"), "status": .string("in_progress")]
        XCTAssertThrowsError(try VyronDevelopmentPlanTool.decode(planCall([active, otherActive])))
        let tooMany = (0..<13).map { ["step": DevelopmentJSONValue.string("Stage \($0)"), "status": .string("pending")] }
        XCTAssertThrowsError(try VyronDevelopmentPlanTool.decode(planCall(tooMany)))
        XCTAssertThrowsError(try VyronDevelopmentPlanTool.decode(planCall([
            ["step": .string("Invalid"), "status": .string("done")]
        ])))
    }

    func testFileEvidenceReplacesSamePathAndDoesNotImplyFreshContents() throws {
        var state = task()
        let oldContent = "let value = 1\n"
        let newContent = "let value = 2\n"
        try state.recordFile(VyronDevelopmentFileProgress(
            path: "Sources/App.swift", contentHash: VyronDevelopmentFileProgress.hash(content: oldContent)
        ))
        XCTAssertTrue(state.progress.files[0].matches(content: oldContent))
        XCTAssertFalse(state.progress.files[0].matches(content: newContent))
        try state.recordFile(VyronDevelopmentFileProgress(
            path: "Sources/App.swift", contentHash: VyronDevelopmentFileProgress.hash(content: newContent)
        ))
        XCTAssertEqual(state.progress.files.count, 1)
        XCTAssertTrue(state.progress.files[0].matches(content: newContent))
        XCTAssertThrowsError(try state.recordFile(VyronDevelopmentFileProgress(
            path: "../Outside.swift", contentHash: VyronDevelopmentFileProgress.hash(content: newContent)
        )))
    }

    func testCompactSummaryIsBoundedValidUnicodeAndRetainsStageAndResultEvidence() throws {
        var state = task(goal: "Build the application " + String(repeating: "界", count: 2_000))
        try state.updatePlan(VyronDevelopmentPlanUpdate(steps: [
            VyronDevelopmentPlanStep(title: "Implement screens", status: .completed),
            VyronDevelopmentPlanStep(title: "Verify", status: .inProgress)
        ]))
        try state.recordFile(VyronDevelopmentFileProgress(
            path: "Sources/App.swift", contentHash: VyronDevelopmentFileProgress.hash(content: "let value = 1")
        ))
        try state.recordCheck(VyronDevelopmentCheckProgress(
            command: "swift test", result: VyronDevelopmentCheckResult(exitCode: 0, timedOut: false)
        ))
        let summary = state.compactSummary()
        XCTAssertLessThanOrEqual(summary.utf8.count, 4_096)
        XCTAssertTrue(summary.contains("not authorization or fresh file contents"))
        XCTAssertTrue(summary.contains("[completed] Implement screens"))
        XCTAssertTrue(summary.contains("Sources/App.swift"))
        XCTAssertTrue(summary.contains("exit 0"))
        XCTAssertFalse(summary.contains("�"))
        XCTAssertEqual(state.compactSummary(maximumBytes: 0), "")
        XCTAssertLessThanOrEqual(state.compactSummary(maximumBytes: 257).utf8.count, 257)
    }

    func testGuidanceIsPreservedWhileRecentModelDecisionsAreBounded() throws {
        var state = task()
        let instruction = "Do not change public APIs. " + String(repeating: "界", count: 1_000)
        try state.recordGuidance(instruction)
        for index in 0..<30 { state.recordDecision("Decision \(index)") }
        XCTAssertEqual(state.guidance, [instruction])
        XCTAssertEqual(state.progress.context.decisions.count, 16)
        XCTAssertEqual(state.progress.context.decisions.first, "Decision 14")
        let before = state
        XCTAssertThrowsError(try state.recordGuidance(String(repeating: "x", count: 128_001)))
        XCTAssertEqual(state, before)
    }

    private func task(goal: String = "Build the application") -> VyronDevelopmentTaskState {
        VyronDevelopmentTaskState(identity: VyronDevelopmentTaskIdentity(projectPath: projectPath, originalGoal: goal))
    }

    private func store() throws -> VyronDevelopmentTaskStore {
        try VyronDevelopmentTaskStore(directoryURL: directory(), projectPath: projectPath)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("VyronTaskState-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    private func planCall(_ entries: [[String: DevelopmentJSONValue]]) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "update_plan", arguments: ["plan": .array(entries.map(DevelopmentJSONValue.object))])
    }
}
