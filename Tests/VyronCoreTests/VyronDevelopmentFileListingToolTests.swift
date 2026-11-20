import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronDevelopmentFileListingToolTests: XCTestCase {
    func testBoundedDefaultInventoryExposesPythonInADocumentationHeavyProject() async throws {
        let fixture = try fixture()
        let page = try await fixture.workspace.fileListing(VyronDevelopmentFileListingRequest(limit: 300))

        let response = try VyronDevelopmentFileListingToolResponse.encode(page: page, maximumBytes: 4_096)
        let fields = try Self.object(response)
        let paths = try Self.paths(fields)

        XCTAssertLessThanOrEqual(response.utf8.count, 4_096)
        XCTAssertTrue(paths.contains(VyronDevelopmentDiscoveryFixture.sourcePath))
        XCTAssertTrue(paths.contains("README.md"))
        XCTAssertLessThan(paths.count, page.files.count, "This fixture must exercise encoded output fitting")
        XCTAssertEqual(fields["total_matches"] as? Int, fixture.visiblePaths.count)
        XCTAssertEqual(fields["truncated"] as? Bool, true)
        XCTAssertEqual(fields["scan_limited"] as? Bool, false)
        XCTAssertFalse(paths.contains(".env"))
        try fixture.assertUnchanged()
    }

    func testFittedListingCursorReachesEveryEscapedPathWithoutSkippingOrRepeatingEntries() async throws {
        let fixture = try fixture()
        var offset = 0
        var collected: [String] = []
        var batches = 0
        while true {
            let page = try await fixture.workspace.fileListing(VyronDevelopmentFileListingRequest(
                limit: 300, offset: offset
            ))
            let response = try VyronDevelopmentFileListingToolResponse.encode(page: page, maximumBytes: 4_096)
            let fields = try Self.object(response)
            let paths = try Self.paths(fields)
            XCTAssertLessThanOrEqual(response.utf8.count, 4_096)
            XCTAssertEqual(fields["offset"] as? Int, offset)
            XCTAssertEqual(fields["total_matches"] as? Int, fixture.visiblePaths.count)
            collected += paths
            batches += 1
            guard let next = fields["next_offset"] as? Int else { break }
            XCTAssertEqual(next, offset + paths.count, "The cursor must follow emitted entries, not requested ones")
            guard next > offset, batches < 50 else { return XCTFail("Listing pagination did not advance") }
            offset = next
        }

        XCTAssertGreaterThan(batches, 1)
        XCTAssertEqual(collected.count, Set(collected).count)
        XCTAssertEqual(Set(collected), fixture.visiblePaths)
        XCTAssertTrue(collected.contains { $0.contains("検証") && $0.contains("\"quoted\"") })
        try fixture.assertUnchanged()
    }

    func testFilenameQueryMatchesPathsRatherThanPythonMentionsInsideDocumentation() async throws {
        let fixture = try fixture()
        let page = try await fixture.workspace.fileListing(VyronDevelopmentFileListingRequest(
            limit: 300, query: ".PY"
        ))
        let response = try VyronDevelopmentFileListingToolResponse.encode(page: page, maximumBytes: 4_096)
        let fields = try Self.object(response)

        XCTAssertEqual(try Self.paths(fields), [VyronDevelopmentDiscoveryFixture.sourcePath])
        XCTAssertEqual(fields["total_matches"] as? Int, 1)
        XCTAssertTrue(fields["next_offset"] is NSNull)
        XCTAssertEqual(fields["scan_limited"] as? Bool, false)
        try fixture.assertUnchanged()
    }

    /// Scripted inference verifies real native discovery/evidence delivery, not local-model reasoning quality.
    func testAgentDiscoversPythonThenReadsItsActualEvidenceWithoutShellCommandsOrSourceChanges() async throws {
        let fixture = try fixture()
        let provider = VyronAutomaticCycleTestProvider { round, messages in
            try Self.reply(round: round, messages: messages)
        }
        let goal = "Analyze the project code using native discovery and source evidence. Remain read-only."

        let result = try await DevelopmentAgent(client: provider, workspace: fixture.workspace).run(
            goal: goal, model: "fixture-coder", automaticModelSelection: false, effort: .quick,
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        let requests = await provider.recordedRequests()
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.steps, 3)
        XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests.allSatisfy { request in
            request.model == "fixture-coder" && request.effort == .quick
                && request.messages.contains { $0.role == "user" && $0.content.contains(goal) }
        })
        XCTAssertTrue(result.finalMessage.contains(VyronDevelopmentDiscoveryFixture.sourcePath))
        XCTAssertTrue(result.finalMessage.contains("trims whitespace and lowercases"))
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertTrue(result.changedFiles.isEmpty)
        try fixture.assertUnchanged()
    }

    func testCancellationAfterListingPreventsTheReadAndNextInference() async throws {
        let fixture = try fixture()
        let provider = VyronAutomaticCycleTestProvider { round, messages in
            try Self.reply(round: round, messages: messages)
        }
        let task = Task {
            try await DevelopmentAgent(client: provider, workspace: fixture.workspace).run(
                goal: "Analyze the project code without edits.", model: "fixture-coder", effort: .quick,
                onEvent: { event in
                    if event.kind == .toolFinished, event.tool == "list_files" {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                },
                approveCommand: { _ in false }
            )
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled discovery run must not continue to source analysis")
        } catch is CancellationError {}

        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertFalse(requests.flatMap(\.messages).contains { $0.toolName == "read_file" })
        try fixture.assertUnchanged()
    }

    private func fixture() throws -> VyronDevelopmentDiscoveryFixture {
        let fixture = try VyronDevelopmentDiscoveryFixture()
        addTeardownBlock { try fixture.remove() }
        return fixture
    }

    private nonisolated static func reply(round: Int, messages: [DevelopmentMessage]) throws -> DevelopmentMessage {
        switch round {
        case 1:
            return DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(
                name: "list_files", arguments: ["query": .string(".py"), "limit": .number(100)], id: "discover-code"
            )])
        case 2:
            let result = try XCTUnwrap(messages.last { $0.role == "tool" && $0.toolName == "list_files" })
            let fields = try object(result.content)
            let path = try XCTUnwrap(paths(fields).first)
            return DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(
                name: "read_file", arguments: ["path": .string(path)], id: "read-discovered-code"
            )])
        default:
            let result = try XCTUnwrap(messages.last { $0.role == "tool" && $0.toolName == "read_file" })
            let fields = try object(result.content)
            let source = try XCTUnwrap(fields["output"] as? String)
            guard source.contains("def normalize_identifier"), source.contains("return value.strip().lower()") else {
                throw DevelopmentError("The requested source evidence did not reach the model")
            }
            let read = try XCTUnwrap(messages.flatMap { $0.toolCalls ?? [] }.last { $0.function.name == "read_file" })
            guard case .string(let path) = read.function.arguments["path"] else {
                throw DevelopmentError("The discovered source path was not preserved")
            }
            return DevelopmentMessage(role: "assistant", content:
                "\(path): the Python utility trims whitespace and lowercases identifiers. "
                    + "Reviewed that source; the documentation inventory alone is not an exhaustive code review."
            )
        }
    }

    private nonisolated static func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private nonisolated static func paths(_ fields: [String: Any]) throws -> [String] {
        let files = try XCTUnwrap(fields["files"] as? [[String: Any]])
        return try files.map { try XCTUnwrap($0["path"] as? String) }
    }
}
