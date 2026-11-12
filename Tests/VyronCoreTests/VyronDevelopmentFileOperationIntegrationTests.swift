import Foundation
import XCTest
@testable import VyronCore
import VyronDevelopment

final class VyronDevelopmentFileOperationIntegrationTests: XCTestCase, @unchecked Sendable {
    func testReviewModesShowActionAndBothPathsAndTrashUsesInjectedAdapter() async throws {
        for mode in [VyronProjectApprovalMode.askForApproval, .approveForMe] {
            let root = try directory()
            try write("original", at: root.appendingPathComponent("A.txt"))
            try FileManager.default.createDirectory(at: root.appendingPathComponent("Sub"),
                withIntermediateDirectories: false)
            let workspace = try DevelopmentWorkspace(rootURL: root)
            let trashed = VyronSteeringTestLog<URL>()
            try await workspace.configureFileTrash(VyronFileOperationTestTrash(
                destination: root.appendingPathComponent("TestTrash.txt"), failure: .none,
                observe: { trashed.append($0) }
            ))
            let reviews = VyronSteeringTestLog<CommandApproval>()
            let agent = DevelopmentAgent(client: scripted([
                Self.move("A.txt", to: "Sub/A.txt"), Self.rename("Sub/A.txt", to: "B.txt"), Self.trash("Sub/B.txt")
            ]), workspace: workspace)
            try await agent.configureCommandApproval(mode)
            try await agent.configureFileOperationAccess(VyronDevelopmentFileOperationAccess(approve: {
                reviews.append($0); return true
            }))

            let result = try await run(agent)

            XCTAssertTrue(result.isComplete, result.finalMessage)
            XCTAssertEqual(reviews.values.map(\.action), [.moveProjectItem, .renameProjectItem, .trashProjectItem])
            let firstReview = try XCTUnwrap(reviews.values.first)
            XCTAssertTrue(firstReview.command.contains(root.appendingPathComponent("A.txt").path))
            XCTAssertTrue(firstReview.command.contains(root.appendingPathComponent("Sub/A.txt").path))
            XCTAssertEqual(trashed.values.count, 1)
            XCTAssertEqual(try text(root.appendingPathComponent("TestTrash.txt")), "original")
            XCTAssertTrue(try XCTUnwrap(trashed.values.first).path.contains("FileOperationStaging"))
            XCTAssertFalse(exists(root.appendingPathComponent("A.txt")))
            XCTAssertFalse(exists(root.appendingPathComponent("Sub/B.txt")))
        }
    }

    func testFullAccessRunsNativeMoveWithoutReview() async throws {
        let root = try directory()
        try write("original", at: root.appendingPathComponent("A.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let agent = DevelopmentAgent(client: scripted([Self.move("A.txt", to: "B.txt")]), workspace: workspace)
        try await agent.configureCommandApproval(.fullAccess)
        try await agent.configureFileOperationAccess(VyronDevelopmentFileOperationAccess(approve: { _ in
            XCTFail("Full access must not request another native review."); return false
        }))

        let result = try await run(agent)

        XCTAssertTrue(result.isComplete, result.finalMessage)
        XCTAssertFalse(exists(root.appendingPathComponent("A.txt")))
        XCTAssertEqual(try text(root.appendingPathComponent("B.txt")), "original")
    }

    func testDeclinedRenameCannotBeRetriedAsEquivalentMove() async throws {
        let root = try directory()
        try write("original", at: root.appendingPathComponent("A.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let reviews = VyronSteeringTestLog<CommandApproval>()
        let agent = DevelopmentAgent(client: scripted([
            Self.rename("A.txt", to: "B.txt"), Self.move("A.txt", to: "B.txt")
        ]), workspace: workspace)
        try await agent.configureFileOperationAccess(VyronDevelopmentFileOperationAccess(approve: {
            reviews.append($0); return false
        }))

        _ = try await run(agent)

        XCTAssertEqual(reviews.values.count, 1)
        XCTAssertEqual(try text(root.appendingPathComponent("A.txt")), "original")
        XCTAssertFalse(exists(root.appendingPathComponent("B.txt")))
    }

    func testAChangedSourceDuringReviewIsNotMoved() async throws {
        let root = try directory()
        let source = root.appendingPathComponent("A.txt")
        try write("original", at: source)
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let agent = DevelopmentAgent(client: scripted([Self.move("A.txt", to: "B.txt")]), workspace: workspace)
        try await agent.configureFileOperationAccess(VyronDevelopmentFileOperationAccess(approve: { _ in
            do { try Data("user's newer content".utf8).write(to: source); return true }
            catch { XCTFail("Fixture edit failed: \(error)"); return false }
        }))

        _ = try await agent.run(
            goal: "Move A.txt to B.txt.", model: "fixture-coder",
            onEvent: { events.append($0) }, approveCommand: { _ in false }
        )

        XCTAssertEqual(try text(source), "user's newer content")
        XCTAssertFalse(exists(root.appendingPathComponent("B.txt")))
        XCTAssertTrue(events.values.contains { $0.tool == "move_item" && $0.failure != nil })
    }

    func testCancellationDuringReviewIgnoresLateApproval() async throws {
        let root = try directory()
        try write("original", at: root.appendingPathComponent("A.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let review = VyronProjectApprovalTestReview()
        let agent = DevelopmentAgent(client: scripted([Self.move("A.txt", to: "B.txt")]), workspace: workspace)
        try await agent.configureFileOperationAccess(VyronDevelopmentFileOperationAccess(approve: {
            await review.waitForDecision($0)
        }))
        let execution = Task { try await run(agent) }
        do { try await waitUntil { await review.requests.count == 1 } }
        catch {
            execution.cancel(); await review.resolve(false); _ = await execution.result
            throw error
        }
        execution.cancel()
        let result = await execution.result
        await review.resolve(true)

        switch result {
        case .success: XCTFail("Cancellation must stop before the filesystem mutation.")
        case .failure(let error): XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(try text(root.appendingPathComponent("A.txt")), "original")
        XCTAssertFalse(exists(root.appendingPathComponent("B.txt")))
    }

    func testPlanAndUnconfiguredRunsDoNotAdvertiseOrExecuteNativeFileOperations() async throws {
        for mode in [DevelopmentMode.agent, .plan] {
            let root = try directory()
            try write("original", at: root.appendingPathComponent("A.txt"))
            let workspace = try DevelopmentWorkspace(rootURL: root)
            let provider = VyronFileOperationTestProvider(calls: [Self.move("A.txt", to: "B.txt")])
            let agent = DevelopmentAgent(client: provider, workspace: workspace)
            if mode == .plan {
                try await agent.configureFileOperationAccess(VyronDevelopmentFileOperationAccess(approve: { _ in
                    XCTFail("Plan must not request a mutation review."); return true
                }))
            }
            _ = try await agent.run(
                goal: "Inspect the proposed project change.", model: "fixture-coder", mode: mode,
                onEvent: { _ in }, approveCommand: { _ in false }
            )

            let catalogues = await provider.recordedTools()
            XCTAssertFalse(catalogues.isEmpty)
            XCTAssertTrue(catalogues.allSatisfy { Set($0).isDisjoint(with: VyronDevelopmentFileOperationTools.names) })
            XCTAssertEqual(try text(root.appendingPathComponent("A.txt")), "original")
            XCTAssertFalse(exists(root.appendingPathComponent("B.txt")))
        }
    }

    func testNativeOperationMixedWithWriteSkipsTheWholeBatch() async throws {
        let root = try directory()
        try write("original", at: root.appendingPathComponent("A.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let provider = VyronSteeringTestProvider { round, _ in
            round == 1 ? DevelopmentMessage(role: "assistant", toolCalls: [
                Self.move("A.txt", to: "B.txt"),
                DevelopmentToolCall(name: "write_file", arguments: [
                    "path": .string("Notes.txt"), "content": .string("Must not be written.")
                ])
            ]) : DevelopmentMessage(role: "assistant", content: "The invalid batch was not executed.")
        }
        let agent = DevelopmentAgent(client: provider, workspace: workspace)
        try await agent.configureFileOperationAccess(VyronDevelopmentFileOperationAccess(approve: { _ in
            XCTFail("A mixed batch must fail before review."); return true
        }))

        _ = try await run(agent)

        XCTAssertEqual(try text(root.appendingPathComponent("A.txt")), "original")
        XCTAssertFalse(exists(root.appendingPathComponent("B.txt")))
        XCTAssertFalse(exists(root.appendingPathComponent("Notes.txt")))
    }

    func testRepeatedSuccessfulMoveDoesNotConsumeARecreatedSource() async throws {
        let root = try directory()
        try write("original", at: root.appendingPathComponent("A.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let reviews = VyronSteeringTestLog<CommandApproval>()
        let agent = DevelopmentAgent(client: scripted([
            Self.move("A.txt", to: "B.txt"),
            DevelopmentToolCall(name: "write_file", arguments: [
                "path": .string("A.txt"), "content": .string("recreated")
            ]),
            Self.move("A.txt", to: "B.txt")
        ]), workspace: workspace)
        try await agent.configureFileOperationAccess(VyronDevelopmentFileOperationAccess(approve: {
            reviews.append($0); return true
        }))

        let result = try await run(agent)

        XCTAssertTrue(result.isComplete, result.finalMessage)
        XCTAssertEqual(reviews.values.count, 1)
        XCTAssertEqual(try text(root.appendingPathComponent("A.txt")), "recreated")
        XCTAssertEqual(try text(root.appendingPathComponent("B.txt")), "original")
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("VyronFileOperationIntegration-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    private func scripted(_ calls: [DevelopmentToolCall]) -> VyronSteeringTestProvider {
        VyronSteeringTestProvider { round, _ in
            round <= calls.count ? DevelopmentMessage(role: "assistant", toolCalls: [calls[round - 1]])
                : DevelopmentMessage(role: "assistant", content: "The requested file actions are finished.")
        }
    }

    private func run(_ agent: DevelopmentAgent) async throws -> DevelopmentResult {
        try await agent.run(
            goal: "Organize the requested project files.", model: "fixture-coder",
            onEvent: { _ in }, approveCommand: { _ in XCTFail("No shell command is needed."); return false }
        )
    }

    private static func move(_ source: String, to destination: String) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "move_item", arguments: [
            "source": .string(source), "destination": .string(destination)
        ])
    }

    private static func rename(_ path: String, to name: String) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "rename_item", arguments: ["path": .string(path), "new_name": .string(name)])
    }

    private static func trash(_ path: String) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "trash_item", arguments: ["path": .string(path)])
    }

    private func waitUntil(_ condition: @escaping @Sendable () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw DevelopmentError("The test did not reach the native approval review.")
    }

    private func write(_ text: String, at url: URL) throws { try Data(text.utf8).write(to: url) }
    private func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}
