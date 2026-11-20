import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronDevelopmentTaskPageGateTests: XCTestCase {
    func testUnreadTaskCannotBeCompletedOrExecuteProjectActions() async throws {
        for attemptsAction in [false, true] {
            let workspace = try workspace()
            let provider = VyronSteeringTestProvider { _, _ in
                if attemptsAction {
                    return DevelopmentMessage(role: "assistant", toolCalls: [Self.write()])
                }
                return DevelopmentMessage(role: "assistant", content: "The entire task is complete.")
            }
            let result = try await run(provider, workspace: workspace)
            XCTAssertFalse(result.isComplete)
            XCTAssertTrue(result.changedFiles.isEmpty)
            XCTAssertTrue(result.commands.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: workspace.rootURL.appendingPathComponent("Unexpected.swift").path
            ))
        }
    }

    func testBatchWithTheLastTaskPageStillCannotEditBeforeItsContentReachesInference() async throws {
        let workspace = try workspace()
        let blocked = VyronSteeringTestLog<Bool>()
        let provider = VyronSteeringTestProvider { _, messages in
            if let response = messages.last(where: { $0.toolName == "write_file" && $0.role == "tool" }) {
                let fields = try Self.object(response.content)
                blocked.append(fields["ok"] as? Bool == false)
                return DevelopmentMessage(role: "assistant", content: "Original task read; no edits performed.")
            }
            var next = 0
            var last = false
            if let response = messages.last(where: { $0.toolName == "read_task" && $0.role == "tool" }) {
                let fields = try Self.object(response.content)
                next = try XCTUnwrap(fields["next_page"] as? Int)
                let total = try XCTUnwrap(fields["total_pages"] as? Int)
                last = next == total - 1
            }
            var calls = [DevelopmentToolCall(name: "read_task", arguments: ["page": .number(Double(next))])]
            if last { calls.append(Self.write()) }
            return DevelopmentMessage(role: "assistant", toolCalls: calls)
        }
        let result = try await run(provider, workspace: workspace)
        XCTAssertEqual(blocked.values, [true])
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.changedFiles.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: workspace.rootURL.appendingPathComponent("Unexpected.swift").path
        ))
    }

    private func run(_ provider: VyronSteeringTestProvider, workspace: DevelopmentWorkspace) async throws -> DevelopmentResult {
        try await DevelopmentAgent(client: provider, workspace: workspace).run(
            goal: "Analyze without editing.\n" + String(repeating: "context ", count: 3_000),
            model: "fixture-coder", effort: .ultra, mode: .agent,
            onEvent: { _ in }, approveCommand: { _ in false }
        )
    }

    private func workspace() throws -> DevelopmentWorkspace {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VyronPageGate-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return try DevelopmentWorkspace(rootURL: root)
    }

    private nonisolated static func write() -> DevelopmentToolCall {
        DevelopmentToolCall(name: "write_file", arguments: [
            "path": .string("Unexpected.swift"), "content": .string("let unexpected = true\n")
        ])
    }

    private nonisolated static func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}
