import Foundation
import XCTest
import VyronDevelopment

final class VyronFolderCreationTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vyron-folders-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    func testCreatesRelativeNestedFoldersWithSpaces() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try VyronFolderCreation.create(VyronFolderCreationRequest(
            path: "New Projects/Finator", projectURL: root
        ))

        XCTAssertTrue(result.created)
        XCTAssertEqual(result.url.path, root.appendingPathComponent("New Projects/Finator").path)
        XCTAssertEqual(try result.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, true)
    }

    func testCreatesAbsoluteDestinationOutsideSelectedProject() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("Selected", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: false)
        let destination = root.appendingPathComponent("Desktop/Finator", isDirectory: true)

        let result = try VyronFolderCreation.create(VyronFolderCreationRequest(
            path: destination.path, projectURL: project
        ))

        XCTAssertEqual(result.url, destination)
        XCTAssertTrue(result.created)
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("Finator").path))
    }

    func testDestinationValidationDoesNotCreateAnyFolders() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = try VyronFolderCreation.destination(for: VyronFolderCreationRequest(
            path: "Missing/Finator", projectURL: root
        ))

        XCTAssertEqual(destination.path, root.appendingPathComponent("Missing/Finator").path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Missing").path))
    }

    func testHomeShortcutUsesNativeHomeDirectoryWithoutCreatingIt() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "Finator-" + UUID().uuidString
        let expected = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
            .appendingPathComponent("Desktop/" + name, isDirectory: true)

        let result = try VyronFolderCreation.destination(for: VyronFolderCreationRequest(
            path: "~/Desktop/" + name, projectURL: root
        ))

        XCTAssertEqual(result, expected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: expected.path))
    }

    func testRepeatedCreationPreservesExistingContents() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let request = VyronFolderCreationRequest(path: "Finator", projectURL: root)
        let first = try VyronFolderCreation.create(request)
        let existing = first.url.appendingPathComponent("notes.txt")
        let content = Data("existing project content".utf8)
        try content.write(to: existing)

        let repeated = try VyronFolderCreation.create(request)

        XCTAssertTrue(first.created)
        XCTAssertFalse(repeated.created)
        XCTAssertEqual(repeated.url, first.url)
        XCTAssertEqual(try Data(contentsOf: existing), content)
    }

    func testExistingFileCannotBeReplacedOrUsedAsParent() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Finator")
        let content = Data("preserve this file".utf8)
        try content.write(to: file)

        for path in ["Finator", "Finator/Sources"] {
            XCTAssertThrowsError(try VyronFolderCreation.create(VyronFolderCreationRequest(
                path: path, projectURL: root
            )))
        }

        XCTAssertEqual(try Data(contentsOf: file), content)
    }

    func testSymbolicLinkComponentsCannotRedirectCreation() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = try fixture()
        defer { try? FileManager.default.removeItem(at: outside) }
        let link = root.appendingPathComponent("Shortcut", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        for path in ["Shortcut", "Shortcut/Finator", link.appendingPathComponent("Finator").path] {
            XCTAssertThrowsError(try VyronFolderCreation.create(VyronFolderCreationRequest(
                path: path, projectURL: root
            )))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("Finator").path))
    }

    func testDanglingSymbolicLinkCannotBeReplaced() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Missing")
        let link = root.appendingPathComponent("Shortcut")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(try VyronFolderCreation.create(VyronFolderCreationRequest(
            path: "Shortcut/Finator", projectURL: root
        )))

        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
    }

    func testRejectsTraversalSensitiveAndMalformedPaths() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = [
            "", ".", "..", "../Finator", "New/../Finator", "New/./Finator", "New//Finator",
            "New/", "\0Finator", "New\nFinator", "~other/Desktop/Finator", ".ssh/Finator",
            "New/.git/Finator", "credentials/Finator", "secrets.json/Finator", ".env.local/Finator",
            "/", "/Users", "/System", "/Library", "/Applications", "/private", "/private/tmp",
            FileManager.default.homeDirectoryForCurrentUser.path, String(repeating: "a", count: 4_097),
            String(repeating: "folder/", count: 129) + "Finator"
        ]

        for path in paths {
            XCTAssertThrowsError(try VyronFolderCreation.create(VyronFolderCreationRequest(
                path: path, projectURL: root
            )), "Unexpectedly accepted path: \(path)")
        }

        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testCanonicalizesOnlyKnownMacOSTemporaryAlias() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "vyron-no-create-" + UUID().uuidString

        let destination = try VyronFolderCreation.destination(for: VyronFolderCreationRequest(
            path: "/tmp/" + name, projectURL: root
        ))

        XCTAssertEqual(destination.path, "/private/tmp/" + name)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testCancelledCreationDoesNotCreateFolders() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let request = VyronFolderCreationRequest(path: "Canceled/Finator", projectURL: root)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try VyronFolderCreation.create(request)
        }

        do {
            _ = try await task.value
            XCTFail("A canceled folder operation must fail.")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Canceled").path))
        }
    }
}
