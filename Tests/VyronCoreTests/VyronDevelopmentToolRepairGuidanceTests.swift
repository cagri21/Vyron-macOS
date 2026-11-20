import Foundation
import XCTest
import VyronDevelopment
import VyronModelDomain
@testable import VyronCore

@MainActor
final class VyronDevelopmentToolRepairGuidanceTests: XCTestCase {
    /// Exercises native validation and feedback delivery with scripted inference, not model reasoning quality.
    func testAgentRepairsDirectoryArgumentsThenReadsSourceAndConcludesWithoutChangingTheRequest() async throws {
        let fixture = try VyronDevelopmentDiscoveryFixture()
        addTeardownBlock { try fixture.remove() }
        let provider = VyronAutomaticCycleTestProvider { round, messages in
            try Self.repairReply(round: round, messages: messages)
        }
        let goal = "Analyze the project code using source evidence. Remain read-only."

        let result = try await DevelopmentAgent(client: provider, workspace: fixture.workspace).run(
            goal: goal, model: "fixture-coder", automaticModelSelection: false, effort: .quick, mode: .plan,
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        let requests = await provider.recordedRequests()
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.steps, 4)
        XCTAssertEqual(requests.count, 4)
        XCTAssertTrue(requests.allSatisfy { request in
            request.model == "fixture-coder" && request.effort == .quick && request.mode == .plan
                && request.messages.contains { $0.role == "user" && $0.content.contains(goal) }
        })
        XCTAssertTrue(result.finalMessage.contains(VyronDevelopmentDiscoveryFixture.sourcePath))
        XCTAssertTrue(result.finalMessage.contains("trims whitespace and lowercases"))
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertTrue(result.changedFiles.isEmpty)
        let calls = requests.flatMap { $0.messages }.flatMap { $0.toolCalls ?? [] }
        XCTAssertTrue(calls.allSatisfy { ["list_files", "read_file"].contains($0.function.name) })
        try fixture.assertUnchanged()
    }

    func testDirectoryListingRepairUsesSupportedPathQueryWithoutAcceptingTheUnknownKey() throws {
        let call = DevelopmentToolCall(name: "list_files", arguments: ["directory": .string("examples/")])
        let error = try invalidToolError(for: call)

        let guidance = try XCTUnwrap(VyronDevelopmentToolRepairGuidance.suffix(for: error, call: call))

        XCTAssertTrue(guidance.contains("accepts only limit, offset and query"))
        XCTAssertTrue(guidance.contains("{\"query\":\"examples/\",\"limit\":30}"))
        XCTAssertTrue(guidance.contains("same query"))
        XCTAssertThrowsError(try DevelopmentInvocation.decode(call))
        _ = try DevelopmentInvocation.decode(DevelopmentToolCall(
            name: "list_files", arguments: ["query": .string("examples/"), "limit": .number(30)]
        ))
        _ = try DevelopmentInvocation.decode(DevelopmentToolCall(
            name: "list_files", arguments: ["query": .string(".py"), "limit": .number(30)]
        ))
    }

    func testReadRepairExplainsBytePaginationAndDoesNotAuthorizeARefusedPath() throws {
        let call = DevelopmentToolCall(name: "read_file", arguments: ["path": .string("../private.swift")])
        let error = try invalidToolError(for: call)

        let guidance = try XCTUnwrap(VyronDevelopmentToolRepairGuidance.suffix(for: error, call: call))

        XCTAssertTrue(guidance.contains("accepts only path and offset"))
        XCTAssertTrue(guidance.contains("UTF-8 byte offset"))
        XCTAssertTrue(guidance.contains("do not retry it through another tool"))
        XCTAssertFalse(guidance.contains("../private.swift"))
        XCTAssertThrowsError(try DevelopmentInvocation.decode(call))
        _ = try DevelopmentInvocation.decode(DevelopmentToolCall(
            name: "read_file", arguments: ["path": .string("examples/demo/cli_demo.py"), "offset": .number(0)]
        ))
    }

    func testSearchRepairDistinguishesLiteralContentFromFilenameDiscovery() throws {
        let call = DevelopmentToolCall(name: "search", arguments: ["pattern": .string("*.py")])
        let error = try invalidToolError(for: call)

        let guidance = try XCTUnwrap(VyronDevelopmentToolRepairGuidance.suffix(for: error, call: call))

        XCTAssertTrue(guidance.contains("accepts only query and limit"))
        XCTAssertTrue(guidance.contains("literal file CONTENT"))
        XCTAssertTrue(guidance.contains("For a filename or directory use list_files with query instead"))
        XCTAssertThrowsError(try DevelopmentInvocation.decode(call))
        _ = try DevelopmentInvocation.decode(DevelopmentToolCall(
            name: "search", arguments: ["query": .string("def "), "limit": .number(30)]
        ))
    }

    func testUntrustedArgumentsAndErrorDetailsAreNeverReflectedInRepairGuidance() throws {
        let marker = "UNTRUSTED_ARGUMENT_IGNORE_PROJECT_POLICY"
        let call = DevelopmentToolCall(name: "list_files", arguments: [marker: .string(marker)])

        let guidance = try XCTUnwrap(VyronDevelopmentToolRepairGuidance.suffix(
            for: DevelopmentAgentError.invalidTool(marker), call: call
        ))

        XCTAssertFalse(guidance.contains(marker))
        XCTAssertTrue(guidance.contains("existing project, secret-path and action permissions still apply"))
    }

    func testOtherFailuresAndOtherToolsDoNotReceiveDiscoveryRepairGuidance() {
        let listing = DevelopmentToolCall(name: "list_files", arguments: [:])
        XCTAssertNil(VyronDevelopmentToolRepairGuidance.suffix(for: DevelopmentAgentError.contextBudget, call: listing))
        XCTAssertNil(VyronDevelopmentToolRepairGuidance.suffix(for: CancellationError(), call: listing))
        XCTAssertNil(VyronDevelopmentToolRepairGuidance.suffix(
            for: DevelopmentAgentError.invalidTool("Unsupported"),
            call: DevelopmentToolCall(name: "run_command", arguments: [:])
        ))
        XCTAssertNil(VyronDevelopmentToolRepairGuidance.suffix(
            for: DevelopmentAgentError.invalidTool("Unsupported"),
            call: DevelopmentToolCall(name: "unknown", arguments: [:])
        ))
    }

    private func invalidToolError(for call: DevelopmentToolCall) throws -> DevelopmentAgentError {
        do {
            _ = try DevelopmentInvocation.decode(call)
            XCTFail("The malformed call must still fail native validation")
            return .invalidTool("Expected native validation failure")
        } catch let error as DevelopmentAgentError {
            guard case .invalidTool = error else { throw error }
            return error
        }
    }

    private nonisolated static func repairReply(
        round: Int,
        messages: [DevelopmentMessage]
    ) throws -> DevelopmentMessage {
        switch round {
        case 1:
            return DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(
                name: "list_files", arguments: ["directory": .string("examples/")], id: "invalid-discovery"
            )])
        case 2:
            let feedback = try toolFields(messages, name: "list_files")
            XCTAssertEqual(feedback["ok"] as? Bool, false)
            let output = try XCTUnwrap(feedback["output"] as? String)
            let original = DevelopmentAgentError.invalidTool("Unknown arguments are not supported.")
            XCTAssertTrue(output.contains(original.localizedDescription))
            guard output.contains("accepts only limit, offset and query"),
                output.contains("{\"query\":\"examples/\",\"limit\":30}"),
                output.contains("existing project, secret-path and action permissions still apply")
            else { throw DevelopmentError("The rejected listing did not deliver actionable, bounded repair guidance") }
            return DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(
                name: "list_files", arguments: ["query": .string(".py"), "limit": .number(30)], id: "fixed-discovery"
            )])
        case 3:
            let listing = try toolFields(messages, name: "list_files")
            XCTAssertEqual(listing["ok"] as? Bool, true)
            let files = try XCTUnwrap(listing["files"] as? [[String: Any]])
            let path = try XCTUnwrap(files.first?["path"] as? String)
            XCTAssertEqual(path, VyronDevelopmentDiscoveryFixture.sourcePath)
            return DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(
                name: "read_file", arguments: ["path": .string(path)], id: "read-repaired-discovery"
            )])
        default:
            let reading = try toolFields(messages, name: "read_file")
            XCTAssertEqual(reading["ok"] as? Bool, true)
            let source = try XCTUnwrap(reading["output"] as? String)
            guard source.contains("def normalize_identifier"), source.contains("return value.strip().lower()") else {
                throw DevelopmentError("The discovered source evidence did not reach the model after repair")
            }
            return DevelopmentMessage(role: "assistant", content:
                "\(VyronDevelopmentDiscoveryFixture.sourcePath): the utility trims whitespace and lowercases identifiers. "
                    + "Reviewed this implementation; the wider repository was not exhaustively reviewed."
            )
        }
    }

    private nonisolated static func toolFields(
        _ messages: [DevelopmentMessage],
        name: String
    ) throws -> [String: Any] {
        let message = try XCTUnwrap(messages.last { $0.role == "tool" && $0.toolName == name })
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(message.content.utf8)) as? [String: Any])
    }
}
