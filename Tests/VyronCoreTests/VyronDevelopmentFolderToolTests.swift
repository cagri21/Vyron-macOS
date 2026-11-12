import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData
@testable import VyronDevelopment

final class VyronDevelopmentFolderToolTests: XCTestCase, @unchecked Sendable {
    func testConfirmedExistingDestinationBecomesProjectForFileWritesAndCheckpointInFullAccess() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let destination = try folder("Finator", in: root)
        let reviews = VyronSteeringTestLog<CommandApproval>()
        let opened = VyronSteeringTestLog<DevelopmentWorkspace>()
        let provider = scripted([
            Self.openFolder(destination.path),
            Self.write("README.md", content: "# Finator\n")
        ])
        let conversationID = UUID()
        let responseID = UUID()
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureSession(VyronDevelopmentSessionContext(
            conversationID: conversationID, responseID: responseID
        ))
        try await agent.configureCommandApproval(.fullAccess)
        try await agent.configureFolderAccess(VyronDevelopmentFolderAccess(
            approveCreation: { _ in XCTFail("The existing folder must not request creation."); return false },
            openProject: { opened.append($0) }
        ))

        let result = try await run(agent, approveMove: { reviews.append($0); return true })

        XCTAssertTrue(result.isComplete, result.finalMessage)
        XCTAssertEqual(result.changedFiles, ["README.md"])
        XCTAssertEqual(reviews.values.map(\.command), [destination.path])
        XCTAssertEqual(reviews.values.map(\.action), [.moveConversation])
        let adopted = try XCTUnwrap(opened.values.first)
        XCTAssertEqual(adopted.rootURL.path, destination.path)
        XCTAssertEqual(try text(destination.appendingPathComponent("README.md")), "# Finator\n")
        XCTAssertFalse(exists(project.rootURL.appendingPathComponent("README.md")))
        let store = try VyronDevelopmentTaskStore(
            directoryURL: adopted.taskStateDirectoryURL.appendingPathComponent(conversationID.uuidString),
            projectPath: adopted.rootURL.path
        )
        let checkpoint = try XCTUnwrap(store.load(id: responseID))
        XCTAssertEqual(checkpoint.identity.projectPath, adopted.rootURL.path)
        XCTAssertEqual(checkpoint.progress.files.map(\.path), ["README.md"])
        XCTAssertEqual(checkpoint.status, .completed)
    }

    func testDeclinedDestinationKeepsWritesInTheCurrentProjectAndDoesNotAskAgain() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let destination = try folder("Declined", in: root)
        let reviews = VyronSteeringTestLog<CommandApproval>()
        let agent = DevelopmentAgent(client: scripted([
            Self.openFolder(destination.path),
            Self.folder(destination.path, open: true),
            Self.write("README.md", content: "Original project\n")
        ]), workspace: project)
        try await agent.configureFolderAccess(VyronDevelopmentFolderAccess(
            approveCreation: { _ in XCTFail("A move does not request folder creation."); return false },
            openProject: { _ in XCTFail("A declined destination must not be opened.") }
        ))

        _ = try await run(agent, approveMove: { reviews.append($0); return false })

        XCTAssertEqual(reviews.values.map(\.command), [destination.path])
        XCTAssertFalse(exists(destination.appendingPathComponent("README.md")))
        XCTAssertEqual(try text(project.rootURL.appendingPathComponent("README.md")), "Original project\n")
    }

    func testOutsideCreationRequiresConfiguredNativeAccessEvenWithFullAccess() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let destination = root.appendingPathComponent("Unavailable", isDirectory: true)
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let agent = DevelopmentAgent(client: scripted([Self.folder(destination.path)]), workspace: project)
        try await agent.configureCommandApproval(.fullAccess)

        _ = try await agent.run(
            goal: "Create the requested folder.", model: "fixture-coder",
            onEvent: { events.append($0) }, approveCommand: { _ in false }
        )

        XCTAssertFalse(exists(destination))
        XCTAssertTrue(events.values.contains { $0.failure != nil })
    }

    func testPlanModeCannotCreateFoldersUnderFullAccess() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let destination = root.appendingPathComponent("PlanOnly", isDirectory: true)
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let agent = DevelopmentAgent(client: scripted([Self.folder(destination.path)]), workspace: project)
        try await agent.configureCommandApproval(.fullAccess)
        try await agent.configureFolderAccess(VyronDevelopmentFolderAccess(
            approveCreation: { _ in XCTFail("Plan mode must not request a write approval."); return true },
            openProject: { _ in XCTFail("Plan mode must not open a newly created project.") }
        ))

        _ = try await agent.run(
            goal: "Plan a project folder without creating it.", model: "fixture-coder", mode: .plan,
            onEvent: { events.append($0) }, approveCommand: { _ in false }
        )

        XCTAssertFalse(exists(destination))
        XCTAssertTrue(events.values.contains { $0.failure?.contains("Plan mode is read-only") == true })
        let tools = try DevelopmentToolDefinition.available(mode: .plan, externalTools: [])
        XCTAssertFalse(tools.contains { VyronDevelopmentFolderTool.names.contains($0.function.name) })
    }

    func testRepeatedRelativeFolderCreationPreservesExistingContents() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let folder = project.rootURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("Keep this note.\n".utf8).write(to: folder.appendingPathComponent("existing.md"))
        let agent = DevelopmentAgent(client: scripted([
            Self.folder("Notes"), Self.folder("Notes")
        ]), workspace: project)

        let result = try await run(agent)

        XCTAssertTrue(result.isComplete, result.finalMessage)
        XCTAssertEqual(try text(folder.appendingPathComponent("existing.md")), "Keep this note.\n")
        XCTAssertTrue(result.changedFiles.isEmpty)
    }

    func testFullAccessCreatesOutsideFolderWithoutApprovalPrompt() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let destination = root.appendingPathComponent("Automatic", isDirectory: true)
        let agent = DevelopmentAgent(client: scripted([Self.folder(destination.path)]), workspace: project)
        try await agent.configureCommandApproval(.fullAccess)
        try await agent.configureFolderAccess(VyronDevelopmentFolderAccess(
            approveCreation: { _ in XCTFail("Full access must not prompt again."); return false },
            openProject: { _ in XCTFail("Creating a folder alone must not change the project.") }
        ))

        _ = try await run(agent)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testOpeningProjectCannotShareBatchWithAFileWrite() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let destination = try folder("MixedBatch", in: root)
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let provider = VyronSteeringTestProvider { round, _ in
            round == 1
                ? DevelopmentMessage(role: "assistant", toolCalls: [
                    Self.openFolder(destination.path), Self.write("README.md", content: "Local\n")
                ])
                : DevelopmentMessage(role: "assistant", content: "The requested actions were considered.")
        }
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureFolderAccess(VyronDevelopmentFolderAccess(
            approveCreation: { _ in XCTFail("An invalid batch must fail before review."); return true },
            openProject: { _ in XCTFail("An invalid batch must not switch projects.") }
        ))

        _ = try await agent.run(
            goal: "Move this conversation to the existing folder.", model: "fixture-coder",
            onEvent: { events.append($0) }, approveCommand: { _ in
                XCTFail("An invalid batch must not request approval.")
                return false
            }
        )

        XCTAssertFalse(exists(destination.appendingPathComponent("README.md")))
        XCTAssertTrue(events.values.contains { $0.tool == "open_project_folder" && $0.failure != nil })
        XCTAssertFalse(exists(project.rootURL.appendingPathComponent("README.md")))
    }

    func testOpeningAnotherProjectIsRejectedAfterCurrentProjectMutation() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let destination = try folder("TooLate", in: root)
        let agent = DevelopmentAgent(client: scripted([
            Self.write("README.md", content: "Already edited\n"), Self.folder(destination.path, open: true)
        ]), workspace: project)
        try await agent.configureFolderAccess(VyronDevelopmentFolderAccess(
            approveCreation: { _ in XCTFail("A late project switch must fail before review."); return true },
            openProject: { _ in XCTFail("A task with saved edits must retain its project.") }
        ))

        _ = try await run(agent)

        XCTAssertFalse(exists(destination.appendingPathComponent("README.md")))
        XCTAssertEqual(try text(project.rootURL.appendingPathComponent("README.md")), "Already edited\n")
    }

    func testCancellationDuringFolderReviewIgnoresLateApproval() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let destination = try folder("Cancelled", in: root)
        let review = VyronProjectApprovalTestReview()
        let agent = DevelopmentAgent(client: scripted([Self.openFolder(destination.path)]), workspace: project)
        try await agent.configureFolderAccess(VyronDevelopmentFolderAccess(
            approveCreation: { _ in XCTFail("A move does not request folder creation."); return false },
            openProject: { _ in XCTFail("Cancellation must prevent project adoption.") }
        ))
        let execution = Task { try await run(agent, approveMove: { await review.waitForDecision($0) }) }
        do {
            try await waitUntil { await review.requests.count == 1 }
        } catch {
            execution.cancel()
            await review.resolve(false)
            _ = await execution.result
            throw error
        }
        execution.cancel()
        let outcome = await execution.result
        await review.resolve(true)

        switch outcome {
        case .success:
            XCTFail("Cancellation must end the pending folder review.")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "Unexpected cancellation error: \(error)")
        }
        XCTAssertTrue(exists(destination))
    }

    func testOpeningDestinationReplacesRepositoryGuidanceForSubsequentInference() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let originalGuidance = "Original-only coding convention: use the old naming style."
        let destinationGuidance = "Destination-only coding convention: use the Finator naming style."
        try Data(originalGuidance.utf8).write(to: project.rootURL.appendingPathComponent("AGENTS.md"))
        let destination = root.appendingPathComponent("Guided", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        try Data(destinationGuidance.utf8).write(to: destination.appendingPathComponent("AGENTS.md"))
        let provider = scripted([Self.folder(destination.path, open: true)])
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureFolderAccess(VyronDevelopmentFolderAccess(
            approveCreation: { _ in true }, openProject: { _ in }
        ))

        _ = try await run(agent, approveMove: { $0.action == .moveConversation })

        let requests = await provider.recordedRequests()
        let first = try XCTUnwrap(requests.first)
        let last = try XCTUnwrap(requests.last)
        XCTAssertTrue(first.contains { $0.content.contains(originalGuidance) })
        XCTAssertTrue(last.contains { $0.content.contains(destinationGuidance) })
        XCTAssertFalse(last.contains { $0.content.contains(originalGuidance) })
    }

    func testSteeringDuringFolderReviewPreventsStaleCreationAndProjectSwitch() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let destination = try folder("Superseded", in: root)
        let inbox = VyronSteeringInbox()
        let review = VyronProjectApprovalTestReview()
        let provider = scripted([
            Self.openFolder(destination.path), Self.write("README.md", content: "Stay in this project.\n")
        ])
        let agent = DevelopmentAgent(client: provider, workspace: project)
        try await agent.configureFolderAccess(VyronDevelopmentFolderAccess(
            approveCreation: { _ in XCTFail("A move does not request folder creation."); return false },
            openProject: { _ in XCTFail("New guidance must prevent stale project adoption.") }
        ))
        let execution = Task {
            try await agent.run(
                goal: "Move this conversation to the existing folder and write notes.", model: "fixture-coder",
                steeringInbox: inbox, onEvent: { _ in }, approveCommand: { await review.waitForDecision($0) }
            )
        }
        do {
            try await waitUntil { await review.requests.count == 1 }
        } catch {
            execution.cancel()
            await review.resolve(false)
            _ = await execution.result
            throw error
        }
        let update = VyronSteeringMessage(content:
            "Stay in the current project and write README.md here."
        )
        await inbox.append(update)
        await review.resolve(true)
        let result = try await execution.value

        XCTAssertTrue(result.isComplete, result.finalMessage)
        XCTAssertFalse(exists(destination.appendingPathComponent("README.md")))
        XCTAssertEqual(try text(project.rootURL.appendingPathComponent("README.md")), "Stay in this project.\n")
        let requests = await provider.recordedRequests()
        XCTAssertTrue(requests.dropFirst().contains { request in
            request.contains { $0.role == "user" && $0.content.contains(update.content) }
        })
    }

    func testASecondProjectSwitchInTheSameRunIsRejected() async throws {
        let root = try temporaryRoot()
        let project = try workspace(in: root)
        let first = try folder("First", in: root)
        let second = try folder("Second", in: root)
        let opened = VyronSteeringTestLog<DevelopmentWorkspace>()
        let agent = DevelopmentAgent(client: scripted([
            Self.openFolder(first.path), Self.openFolder(second.path),
            Self.write("README.md", content: "First destination\n")
        ]), workspace: project)
        try await agent.configureFolderAccess(VyronDevelopmentFolderAccess(
            approveCreation: { _ in true }, openProject: { opened.append($0) }
        ))

        _ = try await run(agent, approveMove: { approval in
            XCTAssertEqual(approval.command, first.path)
            return true
        })

        XCTAssertEqual(opened.values.map { $0.rootURL.path }, [first.path])
        XCTAssertFalse(exists(second.appendingPathComponent("README.md")))
        XCTAssertEqual(try text(first.appendingPathComponent("README.md")), "First destination\n")
        XCTAssertFalse(exists(project.rootURL.appendingPathComponent("README.md")))
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronFolderTool-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    private func workspace(in root: URL) throws -> DevelopmentWorkspace {
        try DevelopmentWorkspace(rootURL: folder("Original", in: root))
    }

    private func folder(_ name: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func scripted(_ calls: [DevelopmentToolCall]) -> VyronSteeringTestProvider {
        VyronSteeringTestProvider { round, _ in
            round <= calls.count
                ? DevelopmentMessage(role: "assistant", toolCalls: [calls[round - 1]])
                : DevelopmentMessage(role: "assistant", content: "The requested folder operation is finished.")
        }
    }

    private static func folder(_ path: String, open: Bool = false) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "create_folder", arguments: [
            "path": .string(path), "open_as_project": .bool(open)
        ])
    }

    private static func openFolder(_ path: String) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "open_project_folder", arguments: ["path": .string(path)])
    }

    private static func write(_ path: String, content: String) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "write_file", arguments: ["path": .string(path), "content": .string(content)])
    }

    private func run(
        _ agent: DevelopmentAgent,
        approveMove: @escaping @Sendable (CommandApproval) async -> Bool = { _ in
            XCTFail("Unexpected approval request.")
            return false
        }
    ) async throws -> DevelopmentResult {
        try await agent.run(
            goal: "Prepare the requested folder and its notes.", model: "fixture-coder",
            onEvent: { _ in }, approveCommand: approveMove
        )
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    private func waitUntil(_ condition: @Sendable () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The folder action did not reach the expected review state.")
        throw CancellationError()
    }
}
