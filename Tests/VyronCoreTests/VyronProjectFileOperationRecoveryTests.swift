import Foundation
import XCTest
@testable import VyronDevelopment

final class VyronProjectFileOperationRecoveryTests: XCTestCase, @unchecked Sendable {
    func testIntentPersistenceFailureDoesNotMutateTheSource() async throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        try write("Keep", to: project.appendingPathComponent("Note.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: project)
        let prepared = try await workspace.prepareFileOperation(.rename(.init(path: "Note.txt", newName: "Moved.txt")))
        let recordURL = workspace.taskStateDirectoryURL.deletingLastPathComponent()
            .appendingPathComponent("FileOperations/" + prepared.id.uuidString + ".json")
        try FileManager.default.createDirectory(at: recordURL, withIntermediateDirectories: true)

        await expectFailure { _ = try await workspace.performFileOperation(prepared) }

        XCTAssertEqual(try text(project.appendingPathComponent("Note.txt")), "Keep")
        XCTAssertFalse(exists(project.appendingPathComponent("Moved.txt")))
        let disposition = await workspace.fileOperationDisposition(prepared)
        XCTAssertEqual(disposition, .notPerformed)
    }

    func testContentHistoryFailureAfterMoveIsReconciledOnReopenWithoutReplay() async throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        try write("Original", to: project.appendingPathComponent("Note.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: project)
        _ = try await workspace.readFile(path: "Note.txt")
        _ = try await workspace.writeFile(path: "Note.txt", content: "Updated")
        let prepared = try await workspace.prepareFileOperation(.rename(.init(path: "Note.txt", newName: "Moved.txt")))
        let historyURL = workspace.taskStateDirectoryURL.deletingLastPathComponent()
            .appendingPathComponent("changes.json")
        let retainedURL = historyURL.appendingPathExtension("retained")
        try FileManager.default.moveItem(at: historyURL, to: retainedURL)
        try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: false)

        await expectFailure { _ = try await workspace.performFileOperation(prepared) }

        XCTAssertEqual(try text(project.appendingPathComponent("Moved.txt")), "Updated")
        XCTAssertFalse(exists(project.appendingPathComponent("Note.txt")))
        let current = await workspace.changes()
        XCTAssertEqual(current.map(\.path), ["Moved.txt"])
        await expectFailure { _ = try await workspace.performFileOperation(prepared) }
        try FileManager.default.removeItem(at: historyURL)
        try FileManager.default.moveItem(at: retainedURL, to: historyURL)
        let reopened = try DevelopmentWorkspace(rootURL: project)
        let changes = await reopened.changes()
        XCTAssertEqual(changes.map(\.path), ["Moved.txt"])
        let recovery = try await reopened.fileOperationRecovery(id: prepared.id)
        XCTAssertEqual(recovery.disposition, .succeeded)
        XCTAssertEqual(recovery.result?.destinationPath, "Moved.txt")
        let recordedAt = recovery.recordedAt
        let later = try await reopened.fileOperationRecovery(id: prepared.id)
        XCTAssertEqual(later.recordedAt, recordedAt)
    }

    func testKnownStaleAfterDurableIntentDoesNotPermanentlyBlockFreshPreparation() throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        try write("Keep", to: project.appendingPathComponent("Folder/Note.txt"))
        let operations = try VyronProjectFileOperations(
            rootURL: project, journalDirectory: project.appendingPathComponent("Folder/Audit"),
            isAllowedComponent: { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }
        )
        let request = VyronProjectFileOperationRequest.move(.init(sourcePath: "Folder", destinationPath: "Moved"))
        let prepared = try operations.prepare(request)

        XCTAssertThrowsError(try operations.perform(prepared, archivedChanges: []))

        XCTAssertEqual(operations.disposition(prepared), .notPerformed)
        XCTAssertEqual(try operations.journal.load(prepared.id).phase, .notPerformed)
        XCTAssertNoThrow(try operations.prepare(request))
        XCTAssertEqual(try text(project.appendingPathComponent("Folder/Note.txt")), "Keep")
        XCTAssertFalse(exists(project.appendingPathComponent("Moved")))
    }

    func testSuccessfulResultRetainedInUncertainRecordAllowsNextMoveAndReconcilesHistory() async throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        try write("Original", to: project.appendingPathComponent("Note.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: project)
        _ = try await workspace.readFile(path: "Note.txt")
        _ = try await workspace.writeFile(path: "Note.txt", content: "Updated")
        let storage = workspace.taskStateDirectoryURL.deletingLastPathComponent()
        let historyURL = storage.appendingPathComponent("changes.json")
        let originalHistory = try Data(contentsOf: historyURL)
        let prepared = try await workspace.prepareFileOperation(.rename(.init(path: "Note.txt", newName: "Moved.txt")))
        _ = try await workspace.performFileOperation(prepared)
        let journal = VyronProjectFileOperationJournal(
            directoryURL: storage.appendingPathComponent("FileOperations"), rootPath: project.path
        )
        var record = try journal.load(prepared.id)
        record.phase = .uncertain
        try journal.save(record)
        try originalHistory.write(to: historyURL, options: .atomic)
        try FileManager.default.linkItem(
            at: project.appendingPathComponent("Moved.txt"), to: project.appendingPathComponent("Note.txt")
        )
        let reopened = try DevelopmentWorkspace(rootURL: project)
        let restored = await reopened.changes()
        XCTAssertEqual(restored.map(\.path), ["Moved.txt"])
        let recovery = try await reopened.fileOperationRecovery(id: prepared.id)
        XCTAssertEqual(recovery.disposition, .succeeded)
        let next = try await reopened.prepareFileOperation(.rename(.init(path: "Moved.txt", newName: "Final.txt")))

        _ = try await reopened.performFileOperation(next)

        XCTAssertEqual(try text(project.appendingPathComponent("Final.txt")), "Updated")
        XCTAssertEqual(try text(project.appendingPathComponent("Note.txt")), "Updated")
        let changes = await reopened.changes()
        XCTAssertEqual(changes.map(\.path), ["Final.txt"])
    }

    func testRollbackConflictPreservesNewSourceAndStagedPayload() async throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        let source = project.appendingPathComponent("Note.txt")
        try write("Reviewed contents", to: source)
        let workspace = try DevelopmentWorkspace(rootURL: project)
        let observed = VyronSteeringTestLog<URL>()
        try await workspace.configureFileTrash(VyronFileOperationTestTrash(
            destination: root.appendingPathComponent("FakeTrash"), failure: .beforeMove,
            observe: { staged in
                observed.append(staged)
                try Data("New user contents".utf8).write(to: source)
            }
        ))
        let prepared = try await workspace.prepareFileOperation(.trash(.init(path: "Note.txt")))

        await expectFailure { _ = try await workspace.performFileOperation(prepared) }

        XCTAssertEqual(try text(source), "New user contents")
        let staged = try XCTUnwrap(observed.values.first)
        XCTAssertEqual(try text(staged), "Reviewed contents")
        let recovery = try await workspace.fileOperationRecovery(id: prepared.id)
        XCTAssertEqual(recovery.disposition, .uncertain)
        XCTAssertEqual(recovery.preservedItemURL, staged)
    }

    func testRestartAfterStagingExposesPreservedPayloadWithoutReplayingTrash() throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        try write("Preserved across restart", to: project.appendingPathComponent("Note.txt"))
        let directory = root.appendingPathComponent("Audit")
        let operations = try VyronProjectFileOperations(
            rootURL: project, journalDirectory: directory,
            isAllowedComponent: { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }
        )
        let prepared = try operations.prepare(.trash(.init(path: "Note.txt")))
        let staging = try VyronProjectFileStaging(
            rootURL: root.appendingPathComponent("FileOperationStaging"),
            operationID: prepared.id, name: "Note.txt"
        )
        var record = VyronProjectFileJournalRecord(
            identity: .init(rootPath: project.path, operation: prepared),
            phase: .started, result: nil, archivedChanges: []
        )
        record.state.stagedURL = staging.url
        try operations.journal.save(record)
        _ = try operations.access.stage(prepared, in: staging)
        let restarted = try VyronProjectFileOperations(
            rootURL: project, journalDirectory: directory,
            isAllowedComponent: { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }
        )

        let recovery = try restarted.recovery(id: prepared.id)

        XCTAssertEqual(recovery.disposition, .uncertain)
        XCTAssertNil(recovery.result)
        XCTAssertEqual(recovery.preservedItemURL, staging.url)
        XCTAssertEqual(try text(staging.url), "Preserved across restart")
        XCTAssertFalse(exists(project.appendingPathComponent("Note.txt")))
    }

    func testParentSymlinkSwapAfterReviewCannotMoveOutsideContents() async throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        try write("Reviewed", to: project.appendingPathComponent("Folder/Note.txt"))
        let outside = root.appendingPathComponent("Outside")
        try write("Outside", to: outside.appendingPathComponent("Note.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: project)
        let prepared = try await workspace.prepareFileOperation(.move(.init(
            sourcePath: "Folder/Note.txt", destinationPath: "Moved.txt"
        )))
        try FileManager.default.moveItem(
            at: project.appendingPathComponent("Folder"), to: project.appendingPathComponent("RetainedFolder")
        )
        try FileManager.default.createSymbolicLink(
            at: project.appendingPathComponent("Folder"), withDestinationURL: outside
        )

        await expectFailure { _ = try await workspace.performFileOperation(prepared) }

        XCTAssertEqual(try text(outside.appendingPathComponent("Note.txt")), "Outside")
        XCTAssertEqual(try text(project.appendingPathComponent("RetainedFolder/Note.txt")), "Reviewed")
        XCTAssertFalse(exists(project.appendingPathComponent("Moved.txt")))
    }

    func testFullJournalRejectsNewIntentBeforeMutationButAllowsUpdatingExistingRecord() throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        try write("Keep", to: project.appendingPathComponent("Note.txt"))
        let operations = try VyronProjectFileOperations(
            rootURL: project, journalDirectory: root.appendingPathComponent("Audit"),
            isAllowedComponent: { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }
        )
        let prepared = try operations.prepare(.rename(.init(path: "Note.txt", newName: "Moved.txt")))
        try FileManager.default.createDirectory(at: operations.journal.directoryURL, withIntermediateDirectories: true)
        var first: VyronProjectFileJournalRecord?
        for _ in 0..<VyronProjectFileOperationLimits.maximumRecords {
            let operation = VyronPreparedProjectFileOperation(
                id: UUID(), request: prepared.request, snapshot: prepared.snapshot, preparedAt: Date()
            )
            let record = VyronProjectFileJournalRecord(
                identity: .init(rootPath: project.path, operation: operation),
                phase: .notPerformed, result: nil, archivedChanges: []
            )
            if first == nil { first = record }
            try JSONEncoder().encode(record).write(
                to: operations.journal.directoryURL.appendingPathComponent(operation.id.uuidString + ".json")
            )
        }

        XCTAssertThrowsError(try operations.perform(prepared, archivedChanges: []))
        XCTAssertNoThrow(try operations.journal.save(XCTUnwrap(first)))
        XCTAssertEqual(try text(project.appendingPathComponent("Note.txt")), "Keep")
        XCTAssertFalse(exists(project.appendingPathComponent("Moved.txt")))
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronFileRecovery-" + UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Project"), withIntermediateDirectories: true
        )
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func expectFailure(_ action: () async throws -> Void) async {
        do { try await action(); XCTFail("The operation must preserve existing items on failure.") }
        catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    private func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
}
