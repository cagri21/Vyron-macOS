import Foundation
import XCTest
@testable import VyronCore
@testable import VyronDevelopment

final class VyronDevelopmentFolderCheckpointTests: XCTestCase, @unchecked Sendable {
    func testFailedHostAdoptionLeavesNoDestinationCheckpointAndKeepsOriginalFileScope() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronFolderCheckpoint-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let originalURL = root.appendingPathComponent("Original", isDirectory: true)
        let destination = root.appendingPathComponent("RejectedAdoption", isDirectory: true)
        try FileManager.default.createDirectory(at: originalURL, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let original = try DevelopmentWorkspace(rootURL: originalURL)
        let proposed = VyronSteeringTestLog<DevelopmentWorkspace>()
        let provider = VyronSteeringTestProvider { round, _ in
            switch round {
            case 1:
                return DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(
                    name: "open_project_folder", arguments: ["path": .string(destination.path)]
                )])
            case 2:
                return DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(
                    name: "write_file", arguments: [
                        "path": .string("README.md"), "content": .string("The original project remains active.\n")
                    ]
                )])
            default:
                return DevelopmentMessage(role: "assistant", content: "The original project's notes are saved.")
            }
        }
        let conversationID = UUID()
        let responseID = UUID()
        let agent = DevelopmentAgent(client: provider, workspace: original)
        try await agent.configureSession(VyronDevelopmentSessionContext(
            conversationID: conversationID, responseID: responseID
        ))
        try await agent.configureFolderAccess(VyronDevelopmentFolderAccess(
            approveCreation: { _ in true },
            openProject: { workspace in
                proposed.append(workspace)
                throw DevelopmentError("The host could not persist the proposed project association.")
            }
        ))

        let result = try await agent.run(
            goal: "Move this conversation to the project folder and write its notes.", model: "fixture-coder",
            onEvent: { _ in }, approveCommand: { $0.action == .moveConversation }
        )

        XCTAssertTrue(result.isComplete, result.finalMessage)
        XCTAssertEqual(proposed.values.count, 1)
        XCTAssertEqual(
            try String(contentsOf: originalURL.appendingPathComponent("README.md"), encoding: .utf8),
            "The original project remains active.\n"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("README.md").path))
        let candidate = try XCTUnwrap(proposed.values.first)
        let destinationStore = try VyronDevelopmentTaskStore(
            directoryURL: candidate.taskStateDirectoryURL.appendingPathComponent(conversationID.uuidString),
            projectPath: candidate.rootURL.path
        )
        XCTAssertNil(try destinationStore.load(id: responseID))
        let originalStore = try VyronDevelopmentTaskStore(
            directoryURL: original.taskStateDirectoryURL.appendingPathComponent(conversationID.uuidString),
            projectPath: original.rootURL.path
        )
        let checkpoint = try XCTUnwrap(originalStore.load(id: responseID))
        XCTAssertEqual(checkpoint.identity.projectPath, original.rootURL.path)
        XCTAssertEqual(checkpoint.progress.files.map(\.path), ["README.md"])
        XCTAssertEqual(checkpoint.status, .completed)
    }
}
