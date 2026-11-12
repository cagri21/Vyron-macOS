import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

final class VyronDevelopmentNoOpTests: XCTestCase, @unchecked Sendable {
    private func workspace() throws -> DevelopmentWorkspace {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VyronNoOp-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return try DevelopmentWorkspace(rootURL: root)
    }

    private func unchangedEdit() -> DevelopmentToolCall {
        DevelopmentToolCall(name: "edit_file", arguments: [
            "path": .string("Feature.swift"), "old_text": .string("value = 1"), "new_text": .string("value = 1")
        ], id: "unchanged-edit")
    }

    func testObservedUnchangedEditDoesNotWriteOrCreateAChangeRecord() async throws {
        let project = try workspace()
        let source = project.rootURL.appendingPathComponent("Feature.swift")
        let content = "let value = 1\n"
        try Data(content.utf8).write(to: source)
        let call = unchangedEdit()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let provider = VyronSteeringTestProvider { round, _ in
            switch round {
            case 1:
                return DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(
                    name: "read_file", arguments: ["path": .string("Feature.swift")]
                )])
            case 2: return DevelopmentMessage(role: "assistant", toolCalls: [call])
            default: return DevelopmentMessage(role: "assistant", content: "The source already matches.")
            }
        }

        let result = try await DevelopmentAgent(client: provider, workspace: project).run(
            goal: "Check the existing value without changing it.", model: "fixture-coder",
            onEvent: { events.append($0) }, approveCommand: { _ in false }
        )

        XCTAssertTrue(result.changedFiles.isEmpty)
        XCTAssertFalse(events.values.contains { $0.kind == .fileChanged })
        let changes = await project.changes()
        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), content)
    }

    func testUnchangedEditStillRequiresAnObservedUniqueFragment() async throws {
        let project = try workspace()
        try Data("let value = 1\n".utf8).write(to: project.rootURL.appendingPathComponent("Feature.swift"))
        let call = unchangedEdit()
        let provider = VyronSteeringTestProvider { round, _ in
            round == 1 ? DevelopmentMessage(role: "assistant", toolCalls: [call])
                : DevelopmentMessage(role: "assistant", content: "A current read is required.")
        }

        _ = try await DevelopmentAgent(client: provider, workspace: project).run(
            goal: "Check the existing value.", model: "fixture-coder",
            onEvent: { _ in }, approveCommand: { _ in false }
        )

        let requests = await provider.recordedRequests()
        let refused = try XCTUnwrap(requests[1].first { $0.toolCallID == call.id })
        XCTAssertTrue(refused.content.contains("\"ok\":false"))
        XCTAssertTrue(refused.content.contains("Read the current file"))
    }

    func testCheckpointHashCheckDetectsChangesWithoutGrantingEditReadPermission() async throws {
        let project = try workspace()
        let path = "Feature.swift"
        let source = project.rootURL.appendingPathComponent(path)
        let content = "let value = 1\n"
        let hash = VyronDevelopmentFileProgress.hash(content: content)
        try Data(content.utf8).write(to: source)

        let matches = try await project.fileMatchesRecordedHash(path: path, contentHash: hash)
        XCTAssertTrue(matches)
        do {
            _ = try await project.writeFile(path: path, content: "let value = 2\n")
            XCTFail("Checkpoint evidence must not authorize overwriting an unread file")
        } catch let error as DevelopmentError {
            XCTAssertTrue(error.message.contains("Read the complete current file"))
        }
        try Data("let value = 3\n".utf8).write(to: source)
        let changed = try await project.fileMatchesRecordedHash(path: path, contentHash: hash)
        XCTAssertFalse(changed)
    }
}
