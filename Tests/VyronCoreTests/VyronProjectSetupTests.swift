import Darwin
import Foundation
import XCTest
import VyronDevelopment

final class VyronProjectSetupTests: XCTestCase {
    private let setupPaths = ["AGENTS.md", "README.md", "PLANS.md", ".gitignore"]

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vyron-project-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testEmptyProjectCreatesUsefulGuidanceAndSetupFiles() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let result = try VyronProjectSetup.prepare(at: root)

        XCTAssertEqual(result.createdPaths, setupPaths)
        XCTAssertTrue(result.preservedPaths.isEmpty)
        let agents = try String(contentsOf: root.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        XCTAssertTrue(agents.contains("README.md"))
        XCTAssertTrue(agents.contains("PLANS.md"))
        XCTAssertTrue(agents.contains("No supported root manifest was detected"))
        XCTAssertTrue(agents.contains("preserve unrelated work"))
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertTrue(readme.hasPrefix("# " + root.lastPathComponent))
        XCTAssertTrue(readme.contains("No setup commands have"))
        let plans = try String(contentsOf: root.appendingPathComponent("PLANS.md"), encoding: .utf8)
        XCTAssertTrue(plans.contains("checks that remain blocked"))
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8),
            "# Local operating-system metadata\n.DS_Store\n"
        )
    }

    func testExistingFilesIncludingEmptyAndNonUTF8ArePreservedByteForByte() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = [Data(), Data([0, 255, 1]), Data("custom plan\r\n".utf8), Data("tracked/\n".utf8)]
        for (path, data) in zip(setupPaths, original) {
            try data.write(to: root.appendingPathComponent(path))
        }

        let result = try VyronProjectSetup.prepare(at: root)

        XCTAssertTrue(result.createdPaths.isEmpty)
        XCTAssertEqual(result.preservedPaths, setupPaths)
        for (path, data) in zip(setupPaths, original) {
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), data)
        }
    }

    func testPartiallyInitializedProjectCreatesOnlyMissingFilesAndReAddIsIdempotent() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("# Existing instructions\n".utf8)
        try original.write(to: root.appendingPathComponent("AGENTS.md"))

        let first = try VyronProjectSetup.prepare(at: root)
        let generated = try setupPaths.map { try Data(contentsOf: root.appendingPathComponent($0)) }
        let second = try VyronProjectSetup.prepare(at: root)

        XCTAssertEqual(first.createdPaths, ["README.md", "PLANS.md", ".gitignore"])
        XCTAssertEqual(first.preservedPaths, ["AGENTS.md"])
        XCTAssertTrue(second.createdPaths.isEmpty)
        XCTAssertEqual(second.preservedPaths, setupPaths)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("AGENTS.md")), original)
        XCTAssertEqual(try setupPaths.map { try Data(contentsOf: root.appendingPathComponent($0)) }, generated)
    }

    func testExistingSymlinksAndDirectoriesArePreservedWithoutFollowingThem() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = try fixture()
        defer { try? FileManager.default.removeItem(at: outside) }
        let target = outside.appendingPathComponent("original.md")
        let original = Data("keep this target".utf8)
        try original.write(to: target)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("AGENTS.md"), withDestinationURL: target
        )
        let missing = outside.appendingPathComponent("not-created.md")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("README.md"), withDestinationURL: missing
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("PLANS.md"), withIntermediateDirectories: false
        )

        let result = try VyronProjectSetup.prepare(at: root)

        XCTAssertEqual(result.createdPaths, [".gitignore"])
        XCTAssertEqual(result.preservedPaths, ["AGENTS.md", "README.md", "PLANS.md"])
        XCTAssertEqual(try Data(contentsOf: target), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent("AGENTS.md").path),
            target.path
        )
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent("README.md").path),
            missing.path
        )
        let directory = try root.appendingPathComponent("PLANS.md").resourceValues(forKeys: [.isDirectoryKey])
        XCTAssertEqual(directory.isDirectory, true)
    }

    func testManifestDetectionUsesRegularRootFilesWithoutInventingCommands() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["Package.swift", "package.json", "pyproject.toml", "Cargo.toml"] {
            try Data("not evaluated or parsed".utf8).write(to: root.appendingPathComponent(path))
        }

        _ = try VyronProjectSetup.prepare(at: root)

        let agents = try String(contentsOf: root.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        let ignore = try String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8)
        for path in ["Package.swift", "package.json", "pyproject.toml", "Cargo.toml"] {
            XCTAssertTrue(agents.contains("`" + path + "`"))
        }
        for path in [".build/", "node_modules/", ".venv/", "target/"] {
            XCTAssertTrue(ignore.contains(path))
        }
        XCTAssertFalse(agents.contains("npm test"))
        XCTAssertFalse(agents.contains("not evaluated or parsed"))
    }

    func testSymlinkedAndDirectoryManifestsAreNotUsedForDetection() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = try fixture()
        defer { try? FileManager.default.removeItem(at: outside) }
        let target = outside.appendingPathComponent("manifest.json")
        try Data("private contents".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("package.json"), withDestinationURL: target
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Package.swift"), withIntermediateDirectories: false
        )

        _ = try VyronProjectSetup.prepare(at: root)

        let agents = try String(contentsOf: root.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        let ignore = try String(contentsOf: root.appendingPathComponent(".gitignore"), encoding: .utf8)
        XCTAssertTrue(agents.contains("No supported root manifest was detected"))
        XCTAssertFalse(ignore.contains("node_modules/"))
        XCTAssertFalse(ignore.contains(".build/"))
    }

    func testUnsafeOrInvalidRootsAreRejected() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let alias = root.appendingPathComponent("Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        let file = root.appendingPathComponent("file")
        try Data().write(to: file)

        for url in [alias, file, URL(fileURLWithPath: "/"), FileManager.default.homeDirectoryForCurrentUser] {
            XCTAssertThrowsError(try VyronProjectSetup.prepare(at: url))
        }
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com"))
        XCTAssertThrowsError(try VyronProjectSetup.prepare(at: remoteURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("AGENTS.md").path))
    }

    func testReadOnlyRootReportsFailureWithoutCreatingFiles() throws {
        if getuid() == 0 { throw XCTSkip("Root can bypass directory write permissions.") }
        let root = try fixture()
        defer {
            chmod(root.path, 0o700)
            try? FileManager.default.removeItem(at: root)
        }
        XCTAssertEqual(chmod(root.path, 0o500), 0)

        XCTAssertThrowsError(try VyronProjectSetup.prepare(at: root)) { error in
            XCTAssertEqual((error as NSError).domain, NSPOSIXErrorDomain)
            XCTAssertEqual((error as NSError).code, Int(EACCES))
        }

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testConcurrentPreparationCreatesEachFileExactlyOnce() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let results = try await withThrowingTaskGroup(of: VyronProjectSetupResult.self) { group in
            for _ in 0..<12 {
                group.addTask { try VyronProjectSetup.prepare(at: root) }
            }
            var values: [VyronProjectSetupResult] = []
            for try await value in group { values.append(value) }
            return values
        }

        let created = results.flatMap(\.createdPaths)
        XCTAssertEqual(created.count, setupPaths.count)
        XCTAssertEqual(Set(created), Set(setupPaths))
        for result in results {
            XCTAssertEqual(Set(result.createdPaths + result.preservedPaths), Set(setupPaths))
        }
        for path in setupPaths {
            let contents = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertFalse(contents.isEmpty)
            XCTAssertTrue(contents.hasSuffix("\n"))
        }
    }
}
