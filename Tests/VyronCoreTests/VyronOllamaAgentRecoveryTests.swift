import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronOllamaAgentRecoveryTests: XCTestCase {
    override func tearDown() {
        VyronOllamaDevelopmentRepairURLProtocol.state.reset()
        super.tearDown()
    }

    func testExhaustedAdapterRepairRecoversFromCheckpointWithoutReplayingWrites() async throws {
        let project = try workspace()
        let session = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let note = "RecoveryNote.txt"
        let content = "This note must be written exactly once.\n"
        let write = DevelopmentToolCall(name: "write_file", arguments: [
            "path": .string(note), "content": .string(content)
        ], id: "original-file-write")
        let create = DevelopmentToolCall(name: "mcp_recovery_create", arguments: [:], id: "original-integration")
        let repeatedWrite = DevelopmentToolCall(
            name: write.function.name, arguments: write.function.arguments, id: "repeated-file-write"
        )
        let repeatedCreate = DevelopmentToolCall(
            name: create.function.name, arguments: create.function.arguments, id: "repeated-integration"
        )
        let first = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", toolCalls: [write, create])
        )
        let empty = try blankReply()
        let repeated = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", toolCalls: [repeatedWrite, repeatedCreate])
        )
        let final = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", content: "The original note and resource are ready.")
        )
        let replies = [first, empty, empty, repeated, final]
        VyronOllamaDevelopmentRepairURLProtocol.state.configure { attempt, _ in
            replies[min(attempt - 1, replies.count - 1)]
        }
        let executed = VyronSteeringTestLog<DevelopmentToolCall>()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let inbox = VyronSteeringInbox()
        let guidance = "Keep the existing note and exact resource identity; do not create replacements."
        await inbox.append(VyronSteeringMessage(content: guidance))
        let agent = DevelopmentAgent(client: try VyronOllamaDevelopmentRepairFixture.client(), workspace: project)
        try await agent.configureSession(session)
        let goal = "Create one project note and exactly one fixture resource, then report the result."

        let result = try await agent.run(
            goal: goal,
            model: VyronOllamaDevelopmentRepairFixture.model,
            automaticModelSelection: false,
            externalTools: [externalTool()],
            executeExternalTool: { call in
                executed.append(call)
                return DevelopmentExternalResult(text: "Created RECOVERY_RESOURCE_EXACT_73.")
            },
            steeringInbox: inbox,
            onEvent: { events.append($0) },
            approveCommand: { _ in false }
        )

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.changedFiles, [note])
        XCTAssertEqual(executed.values, [create])
        XCTAssertEqual(events.values.filter { $0.kind == .fileChanged }.count, 1)
        XCTAssertEqual(try String(contentsOf: project.rootURL.appendingPathComponent(note), encoding: .utf8), content)
        let requests = VyronOllamaDevelopmentRepairURLProtocol.state.requests
        XCTAssertEqual(requests.count, 5)
        let recovered = try VyronOllamaDevelopmentRepairFixture.messages(in: XCTUnwrap(requests.dropFirst(3).first))
        XCTAssertTrue(recovered.contains { $0.role == "user" && $0.content == goal })
        XCTAssertTrue(recovered.contains { $0.role == "user" && $0.content.contains(guidance) })
        XCTAssertTrue(recovered.contains { $0.role == "system" && $0.content.contains("Saved task checkpoint") })
        XCTAssertTrue(recovered.contains { $0.content.contains("RECOVERY_RESOURCE_EXACT_73") })
        XCTAssertTrue(recovered.contains { $0.content.contains(note) })
        let saved = try checkpoint(in: project, session: session)
        XCTAssertEqual(saved.status, .completed)
        XCTAssertEqual(saved.progress.files.count, 1)
        XCTAssertEqual(saved.progress.integrations.count, 1)
        XCTAssertTrue(saved.progress.integrations[0].summary.contains("RECOVERY_RESOURCE_EXACT_73"))
        XCTAssertTrue(requests.allSatisfy { !String(decoding: $0, as: UTF8.self).contains("PRIVATE_AGENT_THINKING") })
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(saved), as: UTF8.self).contains("PRIVATE_AGENT_THINKING"))
    }

    func testAlwaysBlankOllamaStopsAfterTheSharedBoundedAgentRecoveryAllowance() async throws {
        let empty = try blankReply()
        VyronOllamaDevelopmentRepairURLProtocol.state.configure { _, _ in empty }
        let project = try workspace()
        let session = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let agent = DevelopmentAgent(client: try VyronOllamaDevelopmentRepairFixture.client(), workspace: project)
        try await agent.configureSession(session)

        do {
            _ = try await agent.run(
                goal: "Inspect the project and give a complete public answer.",
                model: VyronOllamaDevelopmentRepairFixture.model,
                automaticModelSelection: false,
                onEvent: { _ in }, approveCommand: { _ in false }
            )
            XCTFail("Repeated blank HTTP completions must leave the task unfinished.")
        } catch LocalAIError.invalidResponse(let detail) {
            XCTAssertEqual(detail, "The local model finished without an answer or a native tool call.")
        }

        XCTAssertEqual(VyronOllamaDevelopmentRepairURLProtocol.state.requests.count, 6)
        let saved = try checkpoint(in: project, session: session)
        XCTAssertEqual(saved.status, .failed)
    }

    func testHTTPFailureDoesNotStartAgentRecovery() async throws {
        let error = try await failure(for: blankReply(), status: 500)
        XCTAssertEqual(error as? ModelProviderError, .http(500))
    }

    func testMalformedJSONDoesNotStartAgentRecovery() async throws {
        let error = try await failure(for: Data("{malformed".utf8))
        XCTAssertTrue(error is DecodingError, "Unexpected malformed-response error: \(error)")
    }

    func testLifecycleRepliesDoNotStartAgentRecovery() async throws {
        for reason in ["load", "unload", "unexpected"] {
            let reply = try VyronOllamaDevelopmentRepairFixture.reply(
                DevelopmentMessage(role: "assistant"), reason: reason
            )
            let error = try await failure(for: reply)
            XCTAssertEqual(
                error as? LocalAIError,
                .invalidResponse("The local model finished without an answer or a native tool call.")
            )
        }
    }

    func testCancellationDuringAgentRecoveryPreventsAnotherHTTPRepairOrAction() async throws {
        let empty = try blankReply()
        let project = try workspace()
        let session = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        let agent = DevelopmentAgent(client: try VyronOllamaDevelopmentRepairFixture.client(), workspace: project)
        try await agent.configureSession(session)
        let operation = Task {
            try await agent.run(
                goal: "Inspect the project without making changes.",
                model: VyronOllamaDevelopmentRepairFixture.model,
                automaticModelSelection: false,
                onEvent: { _ in }, approveCommand: { _ in false }
            )
        }
        VyronOllamaDevelopmentRepairURLProtocol.state.configure { attempt, _ in
            if attempt == 3 { operation.cancel() }
            return empty
        }

        do {
            _ = try await operation.value
            XCTFail("Cancellation during checkpoint recovery must stop inference.")
        } catch {
            XCTAssertTrue(error is CancellationError, "Unexpected recovery cancellation error: \(error)")
        }

        XCTAssertEqual(VyronOllamaDevelopmentRepairURLProtocol.state.requests.count, 3)
        let changes = await project.changes()
        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(try checkpoint(in: project, session: session).status, .stopped)
    }

    private func failure(for reply: Data, status: Int = 200) async throws -> Error {
        VyronOllamaDevelopmentRepairURLProtocol.state.configure(status: status) { _, _ in reply }
        let project = try workspace()
        let agent = DevelopmentAgent(client: try VyronOllamaDevelopmentRepairFixture.client(), workspace: project)
        do {
            _ = try await agent.run(
                goal: "Inspect the project.", model: VyronOllamaDevelopmentRepairFixture.model,
                automaticModelSelection: false,
                onEvent: { _ in }, approveCommand: { _ in false }
            )
            XCTFail("A protocol failure must propagate instead of producing a successful task.")
        } catch {
            XCTAssertEqual(VyronOllamaDevelopmentRepairURLProtocol.state.requests.count, 1)
            return error
        }
        throw URLError(.badServerResponse)
    }

    private func blankReply() throws -> Data {
        try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant"), thinking: "PRIVATE_AGENT_THINKING", reason: "stop"
        )
    }

    private func externalTool() -> DevelopmentExternalTool {
        DevelopmentExternalTool(
            name: "mcp_recovery_create", description: "Create one fixture resource",
            inputSchema: ["type": .string("object")], isReadOnly: false
        )
    }

    private func checkpoint(
        in project: DevelopmentWorkspace,
        session: VyronDevelopmentSessionContext
    ) throws -> VyronDevelopmentTaskState {
        let store = try VyronDevelopmentTaskStore(
            directoryURL: project.taskStateDirectoryURL.appendingPathComponent(session.conversationID.uuidString),
            projectPath: project.rootURL.path
        )
        return try XCTUnwrap(store.load(id: session.responseID))
    }

    private func workspace() throws -> DevelopmentWorkspace {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronOllamaAgentRecovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return try DevelopmentWorkspace(rootURL: directory)
    }
}
