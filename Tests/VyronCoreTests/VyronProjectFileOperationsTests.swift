import Darwin
import Foundation
import XCTest
@testable import VyronDevelopment

final class VyronProjectFileOperationsTests: XCTestCase, @unchecked Sendable {
    func testMoveFolderPreservesContentsAndRelocatesPendingEditsAcrossReopen() async throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        try write("Original\n", to: project.appendingPathComponent("Sources/Note.txt"))
        try write("Untouched\n", to: project.appendingPathComponent("Sources/Keep.txt"))
        try write("Finder metadata", to: project.appendingPathComponent("Sources/.DS_Store"))
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("Archive"), withIntermediateDirectories: false
        )
        let workspace = try DevelopmentWorkspace(rootURL: project)
        _ = try await workspace.readFile(path: "Sources/Note.txt")
        _ = try await workspace.writeFile(path: "Sources/Note.txt", content: "Updated\n")
        let prepared = try await workspace.prepareFileOperation(.move(.init(
            sourcePath: "Sources", destinationPath: "Archive/Moved"
        )))

        let result = try await workspace.performFileOperation(prepared)

        XCTAssertEqual(result.sourcePath, "Sources")
        XCTAssertEqual(result.destinationPath, "Archive/Moved")
        XCTAssertTrue(result.affectedFilePaths.contains("Archive/Moved/Note.txt"))
        XCTAssertFalse(exists(project.appendingPathComponent("Sources")))
        XCTAssertEqual(try text(project.appendingPathComponent("Archive/Moved/Keep.txt")), "Untouched\n")
        XCTAssertEqual(try text(project.appendingPathComponent("Archive/Moved/.DS_Store")), "Finder metadata")
        let changes = await workspace.changes()
        XCTAssertEqual(changes.map(\.path), ["Archive/Moved/Note.txt"])
        await expectFailure {
            _ = try await workspace.writeFile(path: "Archive/Moved/Note.txt", content: "No fresh read\n")
        }
        let reopened = try DevelopmentWorkspace(rootURL: project)
        let restored = await reopened.changes()
        XCTAssertEqual(restored.map(\.path), ["Archive/Moved/Note.txt"])
        let recovery = try await reopened.fileOperationRecovery(id: result.id)
        XCTAssertEqual(recovery.disposition, .succeeded)
        XCTAssertEqual(recovery.result, result)
        XCTAssertLessThanOrEqual(recovery.recordedAt, Date())
    }

    func testRenameRefusesConflictAndPathNamesWithoutChangingEitherFile() async throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        try write("First", to: project.appendingPathComponent("First.txt"))
        try write("Second", to: project.appendingPathComponent("Second.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: project)
        await expectFailure {
            _ = try await workspace.prepareFileOperation(.rename(.init(path: "First.txt", newName: "Second.txt")))
        }
        await expectFailure {
            _ = try await workspace.prepareFileOperation(.rename(.init(path: "First.txt", newName: "../Other.txt")))
        }
        let prepared = try await workspace.prepareFileOperation(.rename(.init(
            path: "First.txt", newName: "Renamed.txt"
        )))

        _ = try await workspace.performFileOperation(prepared)

        XCTAssertEqual(try text(project.appendingPathComponent("Renamed.txt")), "First")
        XCTAssertEqual(try text(project.appendingPathComponent("Second.txt")), "Second")
    }

    func testTrashUsesPrivateStagingAndFakeAdapterAndArchivesPendingChanges() async throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        try write("Original", to: project.appendingPathComponent("Folder/Note.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: project)
        _ = try await workspace.readFile(path: "Folder/Note.txt")
        _ = try await workspace.writeFile(path: "Folder/Note.txt", content: "Updated")
        let destination = root.appendingPathComponent("FakeTrash")
        try await workspace.configureFileTrash(VyronFileOperationTestTrash(
            destination: destination, failure: .none, observe: { url in
                XCTAssertTrue(url.path.contains("/FileOperationStaging/"))
                XCTAssertEqual(url.lastPathComponent, "Folder")
                XCTAssertFalse(url.path.hasPrefix(project.path + "/"))
            }
        ))
        let prepared = try await workspace.prepareFileOperation(.trash(.init(path: "Folder")))

        let result = try await workspace.performFileOperation(prepared)

        XCTAssertEqual(result.recoveryURL, destination)
        XCTAssertEqual(try text(destination.appendingPathComponent("Note.txt")), "Updated")
        XCTAssertFalse(exists(project.appendingPathComponent("Folder")))
        let changes = await workspace.changes()
        XCTAssertTrue(changes.isEmpty)
        let directory = workspace.taskStateDirectoryURL.deletingLastPathComponent()
            .appendingPathComponent("FileOperations")
        let journal = VyronProjectFileOperationJournal(directoryURL: directory, rootPath: project.path)
        XCTAssertEqual(try journal.load(prepared.id).archivedChanges.map(\.path), ["Folder/Note.txt"])
        let reopened = try DevelopmentWorkspace(rootURL: project)
        let restored = await reopened.changes()
        XCTAssertTrue(restored.isEmpty)
    }

    func testRejectsRootTraversalSecretsLinksAndMoveIntoSource() async throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        try write("Safe", to: project.appendingPathComponent("Folder/Note.txt"))
        try write("Secret", to: project.appendingPathComponent(".env"))
        try FileManager.default.createSymbolicLink(
            at: project.appendingPathComponent("Link"), withDestinationURL: root
        )
        let workspace = try DevelopmentWorkspace(rootURL: project)
        for path in ["", ".", "..", "../Outside", "/tmp/Outside", ".env", "Link"] {
            await expectFailure { _ = try await workspace.prepareFileOperation(.trash(.init(path: path))) }
        }
        await expectFailure { _ = try await workspace.prepareFileOperation(.move(.init(
            sourcePath: "Folder", destinationPath: "Folder/Child"
        ))) }
        try FileManager.default.createSymbolicLink(
            at: project.appendingPathComponent("Folder/NestedLink"), withDestinationURL: root
        )
        await expectFailure { _ = try await workspace.prepareFileOperation(.trash(.init(path: "Folder"))) }
        XCTAssertEqual(try text(project.appendingPathComponent("Folder/Note.txt")), "Safe")
    }

    func testChangedSourceAfterReviewRequiresFreshPreparation() async throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        try write("Before", to: project.appendingPathComponent("Note.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: project)
        let request = VyronProjectFileOperationRequest.rename(.init(path: "Note.txt", newName: "Moved.txt"))
        let stale = try await workspace.prepareFileOperation(request)
        try write("After review", to: project.appendingPathComponent("Note.txt"))

        await expectFailure { _ = try await workspace.performFileOperation(stale) }
        let disposition = await workspace.fileOperationDisposition(stale)
        XCTAssertEqual(disposition, .notPerformed)
        let recovery = try await workspace.fileOperationRecovery(id: stale.id)
        XCTAssertEqual(recovery.disposition, .notPerformed)
        let reopened = try DevelopmentWorkspace(rootURL: project)
        let unknown = try await reopened.fileOperationRecovery(id: stale.id)
        XCTAssertEqual(unknown.disposition, .uncertain)
        let fresh = try await workspace.prepareFileOperation(request)
        _ = try await workspace.performFileOperation(fresh)

        XCTAssertEqual(try text(project.appendingPathComponent("Moved.txt")), "After review")
    }

    func testCancellationBeforePerformLeavesSourceAndAllowsFreshReview() async throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        try write("Keep", to: project.appendingPathComponent("Note.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: project)
        let request = VyronProjectFileOperationRequest.rename(.init(path: "Note.txt", newName: "Moved.txt"))
        let prepared = try await workspace.prepareFileOperation(request)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await workspace.performFileOperation(prepared)
        }
        do { _ = try await task.value; XCTFail("A canceled operation must not mutate a file.") }
        catch is CancellationError {}

        XCTAssertEqual(try text(project.appendingPathComponent("Note.txt")), "Keep")
        let disposition = await workspace.fileOperationDisposition(prepared)
        XCTAssertEqual(disposition, .notPerformed)
        let fresh = try await workspace.prepareFileOperation(request)
        _ = try await workspace.performFileOperation(fresh)
        XCTAssertEqual(try text(project.appendingPathComponent("Moved.txt")), "Keep")
    }

    func testCaseAliasedPendingEditMovesToCanonicalDestinationAndCanRevert() async throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        let values = try project.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        guard values.volumeSupportsCaseSensitiveNames == false else {
            throw XCTSkip("The filesystem does not support case aliases.")
        }
        try write("Original", to: project.appendingPathComponent("Sources/Note.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: project)
        _ = try await workspace.readFile(path: "sources/Note.txt")
        _ = try await workspace.writeFile(path: "sources/Note.txt", content: "Updated")
        let prepared = try await workspace.prepareFileOperation(.move(.init(
            sourcePath: "Sources", destinationPath: "Moved"
        )))

        let result = try await workspace.performFileOperation(prepared)

        XCTAssertFalse(prepared.isCaseSensitive)
        XCTAssertTrue(result.impact.containsSource("sources/Note.txt"))
        XCTAssertEqual(result.impact.relocatedPath("sources/Note.txt"), "Moved/Note.txt")
        let changes = await workspace.changes()
        XCTAssertEqual(changes.map(\.path), ["Moved/Note.txt"])
        try await workspace.revert(path: "Moved/Note.txt")
        XCTAssertEqual(try text(project.appendingPathComponent("Moved/Note.txt")), "Original")
    }

    func testCaseSensitiveMatchingPreservesDifferentDirectoryNames() async throws {
        let impact = VyronProjectFileOperationImpact(
            paths: .init(sourcePath: "A", destinationPath: "Moved"), affectedFilePaths: [], isCaseSensitive: true
        )
        XCTAssertTrue(impact.containsSource("A/Note.txt"))
        XCTAssertFalse(impact.containsSource("a/Note.txt"))
        XCTAssertNil(impact.relocatedPath("a/Note.txt"))
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        let values = try project.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        guard values.volumeSupportsCaseSensitiveNames == true else {
            throw XCTSkip("Distinct A/a filesystem entries require a case-sensitive volume.")
        }
        try write("Upper", to: project.appendingPathComponent("A/Note.txt"))
        try write("Lower", to: project.appendingPathComponent("a/Note.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: project)
        _ = try await workspace.readFile(path: "A/Note.txt")
        _ = try await workspace.writeFile(path: "A/Note.txt", content: "Upper edited")
        _ = try await workspace.readFile(path: "a/Note.txt")
        _ = try await workspace.writeFile(path: "a/Note.txt", content: "Lower edited")
        let prepared = try await workspace.prepareFileOperation(.move(.init(
            sourcePath: "A", destinationPath: "Moved"
        )))

        _ = try await workspace.performFileOperation(prepared)

        let changes = await workspace.changes()
        XCTAssertEqual(changes.map(\.path), ["Moved/Note.txt", "a/Note.txt"])
        XCTAssertEqual(try text(project.appendingPathComponent("a/Note.txt")), "Lower edited")
    }

    func testFIFOIsRejectedWithoutBlocking() async throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        let fifo = project.appendingPathComponent("Pipe")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        let workspace = try DevelopmentWorkspace(rootURL: project)
        let started = Date()

        await expectFailure { _ = try await workspace.prepareFileOperation(.trash(.init(path: "Pipe"))) }

        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertTrue(exists(fifo))
    }

    func testTrashFailureRollsBackWithoutReplacingOriginalAndCanBeReviewedAgain() async throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        try write("Keep", to: project.appendingPathComponent("Note.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: project)
        let destination = root.appendingPathComponent("FakeTrash")
        try await workspace.configureFileTrash(VyronFileOperationTestTrash(
            destination: destination, failure: .beforeMove
        ))
        let request = VyronProjectFileOperationRequest.trash(.init(path: "Note.txt"))
        let prepared = try await workspace.prepareFileOperation(request)

        await expectFailure { _ = try await workspace.performFileOperation(prepared) }

        XCTAssertEqual(try text(project.appendingPathComponent("Note.txt")), "Keep")
        let recovery = try await workspace.fileOperationRecovery(id: prepared.id)
        XCTAssertEqual(recovery.disposition, .notPerformed)
        try await workspace.configureFileTrash(VyronFileOperationTestTrash(destination: destination, failure: .none))
        let fresh = try await workspace.prepareFileOperation(request)
        _ = try await workspace.performFileOperation(fresh)
        XCTAssertEqual(try text(destination), "Keep")
    }

    func testUncertainNativeTrashOutcomeCannotReplayAndPreservesRecoveryContents() async throws {
        let root = try fixture()
        let project = root.appendingPathComponent("Project")
        try write("Keep", to: project.appendingPathComponent("Note.txt"))
        let workspace = try DevelopmentWorkspace(rootURL: project)
        let destination = root.appendingPathComponent("FakeTrash")
        try await workspace.configureFileTrash(VyronFileOperationTestTrash(
            destination: destination, failure: .afterMove
        ))
        let request = VyronProjectFileOperationRequest.trash(.init(path: "Note.txt"))
        let prepared = try await workspace.prepareFileOperation(request)

        await expectFailure { _ = try await workspace.performFileOperation(prepared) }

        XCTAssertEqual(try text(destination), "Keep")
        let recovery = try await workspace.fileOperationRecovery(id: prepared.id)
        XCTAssertEqual(recovery.disposition, .uncertain)
        try write("New user file", to: project.appendingPathComponent("Note.txt"))
        await expectFailure { _ = try await workspace.prepareFileOperation(request) }
        XCTAssertEqual(try text(project.appendingPathComponent("Note.txt")), "New user file")
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronFileOperations-" + UUID().uuidString)
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
        do { try await action(); XCTFail("The operation must fail without replacing existing items.") }
        catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    private func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
}
