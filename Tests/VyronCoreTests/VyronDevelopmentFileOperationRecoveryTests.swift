import Foundation
import XCTest
@testable import VyronCore
import VyronDevelopment

final class VyronDevelopmentFileOperationRecoveryTests: XCTestCase, @unchecked Sendable {
    func testRestartReconcilesSuccessfulMoveBeforeTaskEvidenceWasSaved() async throws {
        let root = try directory()
        let workspace = try DevelopmentWorkspace(rootURL: root)
        _ = try await workspace.writeFile(path: "A.txt", content: "original")
        let session = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        var progress = try VyronDevelopmentRunProgress(workspace: workspace, session: session, goal: "Organize files.")
        try progress.recordFile(path: "A.txt", content: "original", changed: true)
        let prepared = try await workspace.prepareFileOperation(.move(VyronProjectFileMoveRequest(
            sourcePath: "A.txt", destinationPath: "B.txt"
        )))
        let identity = VyronDevelopmentFileOperationReview.identity(for: prepared)
        try progress.beginFileOperation(prepared, call: identity)
        _ = try await workspace.performFileOperation(prepared)
        let recovery = try await workspace.fileOperationRecovery(id: prepared.id)

        let reopened = try DevelopmentWorkspace(rootURL: root)
        var resumed = try VyronDevelopmentRunProgress(workspace: reopened, session: session, goal: "Organize files.")
        XCTAssertEqual(resumed.state.progress.files.map(\.path), ["A.txt"])
        XCTAssertEqual(resumed.state.progress.fileOperationIntents.first?.disposition, .pending)
        try await resumed.reconcileFileOperations(in: reopened)

        XCTAssertEqual(resumed.state.progress.files.map(\.path), ["B.txt"])
        XCTAssertEqual(resumed.state.progress.fileOperations.first?.recordedAt, recovery.recordedAt)
        XCTAssertEqual(resumed.state.progress.fileOperationIntents.first?.disposition, .completed)
        XCTAssertEqual(try resumed.previousIntegration(identity)?.status, .succeeded)
        XCTAssertFalse(try resumed.canRetryFileOperation(identity))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("B.txt"), encoding: .utf8), "original")
        let evidenceMatches = try await resumed.fileEvidenceMatches(reopened)
        XCTAssertTrue(evidenceMatches)
    }

    func testKnownNoOpCanRetryButNewDeclineDisablesOldRetryMetadata() async throws {
        let root = try directory()
        let source = root.appendingPathComponent("A.txt")
        try Data("original".utf8).write(to: source)
        let workspace = try DevelopmentWorkspace(rootURL: root)
        var progress = try VyronDevelopmentRunProgress(workspace: workspace, session: nil, goal: "Move A to B.")
        let prepared = try await workspace.prepareFileOperation(.move(VyronProjectFileMoveRequest(
            sourcePath: "A.txt", destinationPath: "B.txt"
        )))
        let identity = VyronDevelopmentFileOperationReview.identity(for: prepared)
        try progress.beginFileOperation(prepared, call: identity)
        try Data("concurrent edit".utf8).write(to: source)
        do {
            _ = try await workspace.performFileOperation(prepared)
            XCTFail("A stale prepared source must not be moved.")
        } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }

        try await progress.reconcileFileOperations(in: workspace)

        XCTAssertTrue(try progress.canRetryFileOperation(identity))
        XCTAssertEqual(progress.state.progress.fileOperationIntents.first?.disposition, .notPerformed)
        try progress.declineFileOperation(identity)
        XCTAssertFalse(try progress.canRetryFileOperation(identity))
        XCTAssertEqual(progress.state.progress.fileOperationIntents.first?.disposition, .declined)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "concurrent edit")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("B.txt").path))
    }

    func testMissingBackendRecordRemainsUncertainAndCannotReplay() async throws {
        let root = try directory()
        try Data("original".utf8).write(to: root.appendingPathComponent("A.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: root)
        let session = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        var progress = try VyronDevelopmentRunProgress(workspace: workspace, session: session, goal: "Move A to B.")
        let prepared = try await workspace.prepareFileOperation(.move(VyronProjectFileMoveRequest(
            sourcePath: "A.txt", destinationPath: "B.txt"
        )))
        let identity = VyronDevelopmentFileOperationReview.identity(for: prepared)
        try progress.beginFileOperation(prepared, call: identity)
        let reopened = try DevelopmentWorkspace(rootURL: root)
        var resumed = try VyronDevelopmentRunProgress(workspace: reopened, session: session, goal: "Move A to B.")

        try await resumed.reconcileFileOperations(in: reopened)

        XCTAssertEqual(resumed.state.progress.fileOperationIntents.first?.disposition, .pending)
        XCTAssertEqual(try resumed.previousIntegration(identity)?.status, .started)
        XCTAssertFalse(try resumed.canRetryFileOperation(identity))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("A.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("B.txt").path))
    }

    func testFailedTaskSaveAfterMoveRetainsIntentAndLaterRecoveryDoesNotMoveAgain() async throws {
        let root = try directory()
        let workspace = try DevelopmentWorkspace(rootURL: root)
        _ = try await workspace.writeFile(path: "A.txt", content: "original")
        let session = VyronDevelopmentSessionContext(conversationID: UUID(), responseID: UUID())
        var progress = try VyronDevelopmentRunProgress(workspace: workspace, session: session, goal: "Organize files.")
        try progress.recordFile(path: "A.txt", content: "original", changed: true)
        let prepared = try await workspace.prepareFileOperation(.move(VyronProjectFileMoveRequest(
            sourcePath: "A.txt", destinationPath: "B.txt"
        )))
        let identity = VyronDevelopmentFileOperationReview.identity(for: prepared)
        try progress.beginFileOperation(prepared, call: identity)
        _ = try await workspace.performFileOperation(prepared)
        let checkpoint = progress.store.directoryURL
            .appendingPathComponent(progress.state.identity.id.uuidString + ".json")
        let retained = progress.store.directoryURL.appendingPathComponent("retained-checkpoint")
        try FileManager.default.moveItem(at: checkpoint, to: retained)
        try FileManager.default.createDirectory(at: checkpoint, withIntermediateDirectories: false)

        do {
            try await progress.reconcileFileOperations(in: workspace)
            XCTFail("The sabotaged checkpoint path must prevent saving task evidence.")
        } catch { XCTAssertTrue(error is VyronDevelopmentCheckpointFailure) }

        XCTAssertEqual(progress.state.progress.fileOperationIntents.first?.disposition, .pending)
        XCTAssertEqual(progress.state.progress.files.map(\.path), ["A.txt"])
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("B.txt"), encoding: .utf8), "original")
        try FileManager.default.removeItem(at: checkpoint)
        try FileManager.default.moveItem(at: retained, to: checkpoint)
        let reopened = try DevelopmentWorkspace(rootURL: root)
        var resumed = try VyronDevelopmentRunProgress(workspace: reopened, session: session, goal: "Organize files.")
        try await resumed.reconcileFileOperations(in: reopened)

        XCTAssertEqual(resumed.state.progress.files.map(\.path), ["B.txt"])
        XCTAssertEqual(resumed.state.progress.fileOperationIntents.first?.disposition, .completed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("A.txt").path))
    }

    func testOutcomeStorageIsReservedBeforeBeginningTheNativeMutation() async throws {
        let root = try directory()
        try Data("original".utf8).write(to: root.appendingPathComponent("A.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: root)
        var progress = try VyronDevelopmentRunProgress(workspace: workspace, session: nil, goal: "Move A to B.")
        let prepared = try await workspace.prepareFileOperation(.move(VyronProjectFileMoveRequest(
            sourcePath: "A.txt", destinationPath: "B.txt"
        )))
        let identity = VyronDevelopmentFileOperationReview.identity(for: prepared)
        let initial = progress.state
        let paddingID = UUID()
        let encoder = JSONEncoder()
        func padded(_ paths: [String]) throws -> VyronDevelopmentTaskState {
            var state = initial
            try state.recordFileOperation(VyronDevelopmentFileOperationEvidence(
                id: paddingID, kind: .move,
                impact: .complete(VyronProjectFileOperationImpact(
                    paths: VyronProjectFileOperationPaths(sourcePath: "ArchivePadding", destinationPath: "KeptPadding"),
                    affectedFilePaths: paths
                )),
                recordedAt: Date(timeIntervalSince1970: 1)
            ))
            return state
        }
        let baseBytes = try encoder.encode(VyronDevelopmentTaskArchive(schemaVersion: 1, task: padded([]))).count
        let prefix = "ArchivePadding/" + String(repeating: "sub/", count: 400)
        let unitBytes = try encoder.encode(prefix + "File0000.txt").count + 1
        let target = VyronDevelopmentTaskLimits.maximumStoredBytes - 1_600
        let count = (target - baseBytes + 1) / unitBytes
        var paths = (0..<count).map { prefix + String(format: "File%04d.txt", $0) }
        let remaining = target - baseBytes - (count * unitBytes - 1)
        let partialPrefix = "ArchivePadding/"
        let partialBytes = try encoder.encode(partialPrefix).count + 1
        if remaining > partialBytes {
            paths.append(partialPrefix + String(repeating: "x", count: remaining - partialBytes))
        }
        progress.state = try padded(paths)
        try progress.save()
        let checkpoint = progress.store.directoryURL
            .appendingPathComponent(progress.state.identity.id.uuidString + ".json")
        let saved = try Data(contentsOf: checkpoint)
        let original = progress.state
        XCTAssertGreaterThan(saved.count, VyronDevelopmentTaskLimits.maximumStoredBytes - 2_000)

        XCTAssertThrowsError(try progress.beginFileOperation(prepared, call: identity))

        XCTAssertEqual(progress.state, original)
        XCTAssertEqual(try Data(contentsOf: checkpoint), saved)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("A.txt"), encoding: .utf8), "original")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("B.txt").path))
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("VyronFileRecovery-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }
}
