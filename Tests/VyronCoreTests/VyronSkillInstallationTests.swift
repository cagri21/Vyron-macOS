import Darwin
import Foundation
import XCTest
@testable import VyronCore

@MainActor
final class VyronSkillInstallationTests: XCTestCase {
    func testInstallsCompletePackageAndRepeatedInstallIsIdempotent() async throws {
        let workspace = try workspace()
        let package = try package(in: workspace)
        try write("Reference instructions", at: package.appendingPathComponent("references/forms.md"))
        try Data([0, 1, 2, 255]).write(to: package.appendingPathComponent("example.bin"))
        try FileManager.default.createDirectory(
            at: package.appendingPathComponent("assets/empty"),
            withIntermediateDirectories: true
        )
        let destination = workspace.appendingPathComponent("home/skills")
        let request = request(package: package, destination: destination)
        let installer = VyronSkillInstaller()

        let result = try await installer.install(request)
        let repeated = try await installer.install(request)

        XCTAssertEqual(result, destination.appendingPathComponent("pdf", isDirectory: true))
        XCTAssertEqual(repeated, result)
        XCTAssertEqual(
            try String(contentsOf: result.appendingPathComponent("references/forms.md"), encoding: .utf8),
            "Reference instructions"
        )
        XCTAssertEqual(try Data(contentsOf: result.appendingPathComponent("example.bin")), Data([0, 1, 2, 255]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.appendingPathComponent("assets/empty").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["pdf"])
    }

    func testEditedExistingSkillIsPreservedAndReportedAsConflict() async throws {
        let workspace = try workspace()
        let package = try package(in: workspace)
        let destination = workspace.appendingPathComponent("skills")
        let request = request(package: package, destination: destination)
        let installer = VyronSkillInstaller()
        let installed = try await installer.install(request)
        let document = installed.appendingPathComponent("SKILL.md")
        let edited = skillDocument + "\nLocal user edits.\n"
        try write(edited, at: document)

        do {
            _ = try await installer.install(request)
            XCTFail("An edited skill must not be replaced")
        } catch {
            XCTAssertEqual(error as? VyronSkillInstallError, .destinationConflict)
        }

        XCTAssertEqual(try String(contentsOf: document, encoding: .utf8), edited)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["pdf"])
    }

    func testChangedSupportingFilesAlsoConflictWithoutReplacingAnything() async throws {
        let workspace = try workspace()
        let package = try package(in: workspace)
        try write("Bundled reference", at: package.appendingPathComponent("references/forms.md"))
        let destination = workspace.appendingPathComponent("skills")
        let request = request(package: package, destination: destination)
        let installer = VyronSkillInstaller()
        let installed = try await installer.install(request)
        let reference = installed.appendingPathComponent("references/forms.md")
        try write("Local reference", at: reference)

        await assertRejected(request, expected: .destinationConflict)

        XCTAssertEqual(try String(contentsOf: reference, encoding: .utf8), "Local reference")
    }

    func testInvalidIdentifiersCannotEscapeInstallationDirectory() async throws {
        let workspace = try workspace()
        let package = try package(in: workspace)
        let destination = workspace.appendingPathComponent("skills")
        for identifier in ["", "../pdf", "/pdf", "pdf/other", "pdf\\other", ".hidden", "PDF", "é", "-pdf"] {
            let request = VyronSkillInstallRequest(
                packageDirectory: package,
                installationDirectory: destination,
                identifier: identifier
            )
            await assertRejected(request, expected: .invalidIdentifier)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testMissingMalformedBinaryAndWrongIdentityPackagesAreRejected() async throws {
        let workspace = try workspace()
        let package = workspace.appendingPathComponent("package")
        let destination = workspace.appendingPathComponent("skills")
        let request = request(package: package, destination: destination)
        await assertRejected(request)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        await assertRejected(request, expected: .invalidPackage)
        let document = package.appendingPathComponent("SKILL.md")
        for content in [
            Data([0xFF]),
            Data("---\nname: pdf\ndescription: Missing boundary".utf8),
            Data("---\nname: other\ndescription: Wrong identity\n---\nBody".utf8),
            Data("---\nname: pdf\ndescription: Valid\n---\n\0".utf8)
        ] {
            try content.write(to: document)
            await assertRejected(request, expected: .invalidPackage)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testRejectsSymlinkedSourceRootAncestorAndSupportingFile() async throws {
        let workspace = try workspace()
        let package = try package(in: workspace)
        let destination = workspace.appendingPathComponent("skills")
        let linked = workspace.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: package)
        await assertRejected(request(package: linked, destination: destination), expected: .unsafePath)
        let ancestor = workspace.appendingPathComponent("ancestor")
        try FileManager.default.createSymbolicLink(at: ancestor, withDestinationURL: workspace)
        await assertRejected(
            request(package: ancestor.appendingPathComponent("package"), destination: destination),
            expected: .unsafePath
        )
        try FileManager.default.createSymbolicLink(
            at: package.appendingPathComponent("reference.md"),
            withDestinationURL: package.appendingPathComponent("SKILL.md")
        )
        await assertRejected(request(package: package, destination: destination), expected: .unsafePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testRejectsSymlinkedDestinationAndDestinationAncestors() async throws {
        let workspace = try workspace()
        let package = try package(in: workspace)
        let outside = workspace.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let destination = workspace.appendingPathComponent("skills")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: destination.appendingPathComponent("pdf"),
            withDestinationURL: outside
        )
        await assertRejected(request(package: package, destination: destination), expected: .unsafePath)
        let linkedRoot = workspace.appendingPathComponent("linked-root")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: outside)
        await assertRejected(
            request(package: package, destination: linkedRoot.appendingPathComponent("nested/skills")),
            expected: .unsafePath
        )
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testRejectsFIFOWithoutBlockingOrLeavingStagingFiles() async throws {
        let workspace = try workspace()
        let package = try package(in: workspace)
        let destination = workspace.appendingPathComponent("skills")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        XCTAssertEqual(mkfifo(package.appendingPathComponent("pipe").path, 0o600), 0)

        await assertRejected(request(package: package, destination: destination), expected: .invalidPackage)

        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }

    func testRejectsOversizedSkillAndSupportingFileBeforeInstallation() async throws {
        let workspace = try workspace()
        let package = try package(in: workspace)
        let destination = workspace.appendingPathComponent("skills")
        let document = package.appendingPathComponent("SKILL.md")
        try write(String(repeating: "a", count: VyronSkillResourceReader.maximumBytes + 1), at: document)
        await assertRejected(request(package: package, destination: destination), expected: .packageTooLarge)
        try write(skillDocument, at: document)
        let oversized = package.appendingPathComponent("oversized.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversized.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(VyronSkillInstallationLimits.maximumFileBytes + 1))
        try handle.close()
        await assertRejected(request(package: package, destination: destination), expected: .packageTooLarge)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testCancellationPreservesDistinctErrorAndLeavesNoInstallation() async throws {
        let workspace = try workspace()
        let package = try package(in: workspace)
        let destination = workspace.appendingPathComponent("skills")
        let request = request(package: package, destination: destination)
        let installer = VyronSkillInstaller()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await installer.install(request)
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled installation must throw")
        } catch is CancellationError {
            // Cancellation is not converted into a package or filesystem failure.
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    private var skillDocument: String {
        "---\nname: pdf\ndescription: Local PDF instructions.\n---\n\n# PDF\n\nReviewed instructions.\n"
    }

    private func workspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("VyronSkillInstallation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func package(in workspace: URL) throws -> URL {
        let directory = workspace.appendingPathComponent("package")
        try write(skillDocument, at: directory.appendingPathComponent("SKILL.md"))
        return directory
    }

    private func write(_ content: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func request(package: URL, destination: URL) -> VyronSkillInstallRequest {
        VyronSkillInstallRequest(packageDirectory: package, installationDirectory: destination, identifier: "pdf")
    }

    private func assertRejected(
        _ request: VyronSkillInstallRequest,
        expected: VyronSkillInstallError? = nil
    ) async {
        do {
            _ = try await VyronSkillInstaller().install(request)
            XCTFail("Expected the package to be rejected")
        } catch {
            if let expected { XCTAssertEqual(error as? VyronSkillInstallError, expected) }
        }
    }
}
