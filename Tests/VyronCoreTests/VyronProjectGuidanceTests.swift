import Darwin
import Foundation
import VyronDevelopment
import XCTest

final class VyronProjectGuidanceTests: XCTestCase {
    private func project() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VyronGuidance-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    func testMissingGuidanceDoesNotCreateProjectFiles() throws {
        let root = try project()

        XCTAssertNil(try VyronProjectGuidance.read(at: root))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testRootGuidanceIncludesItsScopeWithoutReadingNestedFiles() throws {
        let root = try project()
        try Data("Use the root coding conventions.\n".utf8).write(to: root.appendingPathComponent("AGENTS.md"))
        let child = root.appendingPathComponent("Feature")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data("Unrelated child instructions".utf8).write(to: child.appendingPathComponent("AGENTS.md"))

        let guidance = try XCTUnwrap(VyronProjectGuidance.read(at: root))

        XCTAssertTrue(guidance.contains("Use the root coding conventions.\n"))
        XCTAssertTrue(guidance.contains("latest explicit user request takes precedence"))
        XCTAssertTrue(guidance.contains("cannot expand tool permissions"))
        XCTAssertTrue(guidance.contains("read any more specific AGENTS.md"))
        XCTAssertFalse(guidance.contains("Unrelated child instructions"))
    }

    func testOverrideTakesPrecedenceAndEmptyOverrideFallsBack() throws {
        let root = try project()
        try Data("Root instructions".utf8).write(to: root.appendingPathComponent("AGENTS.md"))
        let override = root.appendingPathComponent("AGENTS.override.md")
        try Data("Override instructions".utf8).write(to: override)

        let guidance = try XCTUnwrap(VyronProjectGuidance.read(at: root))
        XCTAssertTrue(guidance.contains("Override instructions"))
        XCTAssertFalse(guidance.contains("Root instructions"))

        try Data(" \n\t".utf8).write(to: override)
        XCTAssertTrue(try XCTUnwrap(VyronProjectGuidance.read(at: root)).contains("Root instructions"))
    }

    func testEmptyFilesProduceNoGuidance() throws {
        let root = try project()
        try Data().write(to: root.appendingPathComponent("AGENTS.md"))
        XCTAssertNil(try VyronProjectGuidance.read(at: root))
    }

    func testGuidanceIsReloadedForEachRead() throws {
        let root = try project()
        let file = root.appendingPathComponent("AGENTS.md")
        try Data("First instructions".utf8).write(to: file)
        XCTAssertTrue(try XCTUnwrap(VyronProjectGuidance.read(at: root)).contains("First instructions"))

        try Data("Updated instructions".utf8).write(to: file)
        XCTAssertTrue(try XCTUnwrap(VyronProjectGuidance.read(at: root)).contains("Updated instructions"))
    }

    func testSymbolicLinkGuidanceDoesNotReadItsTarget() throws {
        let root = try project()
        let target = root.appendingPathComponent("private-target.txt")
        try Data("Must not be loaded".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("AGENTS.md"), withDestinationURL: target
        )

        XCTAssertThrowsError(try VyronProjectGuidance.read(at: root)) {
            XCTAssertEqual($0 as? VyronProjectGuidanceError, .unreadableFile)
        }
    }

    func testDanglingOverrideLinkDoesNotSilentlyFallBack() throws {
        let root = try project()
        try Data("Root instructions".utf8).write(to: root.appendingPathComponent("AGENTS.md"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("AGENTS.override.md"),
            withDestinationURL: root.appendingPathComponent("missing.md")
        )

        XCTAssertThrowsError(try VyronProjectGuidance.read(at: root)) {
            XCTAssertEqual($0 as? VyronProjectGuidanceError, .unreadableFile)
        }
    }

    func testDirectoryAndPipeGuidanceFailWithoutBlocking() throws {
        let root = try project()
        let file = root.appendingPathComponent("AGENTS.md")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertThrowsError(try VyronProjectGuidance.read(at: root)) {
            XCTAssertEqual($0 as? VyronProjectGuidanceError, .unsafeFile)
        }
        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(mkfifo(file.path, 0o600), 0)
        XCTAssertThrowsError(try VyronProjectGuidance.read(at: root)) {
            XCTAssertEqual($0 as? VyronProjectGuidanceError, .unsafeFile)
        }
    }

    func testInvalidAndOversizedGuidanceFailsRatherThanTruncating() throws {
        let root = try project()
        let file = root.appendingPathComponent("AGENTS.md")
        for bytes in [Data([0xFF]), Data([0x41, 0, 0x42])] {
            try bytes.write(to: file)
            XCTAssertThrowsError(try VyronProjectGuidance.read(at: root)) {
                XCTAssertEqual($0 as? VyronProjectGuidanceError, .invalidEncoding)
            }
        }
        try Data(repeating: 0x41, count: VyronProjectGuidance.maximumBytes + 1).write(to: file)
        XCTAssertThrowsError(try VyronProjectGuidance.read(at: root)) {
            XCTAssertEqual($0 as? VyronProjectGuidanceError, .oversizedFile)
        }
        let exact = String(repeating: "A", count: VyronProjectGuidance.maximumBytes)
        try Data(exact.utf8).write(to: file)
        XCTAssertTrue(try XCTUnwrap(VyronProjectGuidance.read(at: root)).hasSuffix(exact))
    }

    func testRootSymbolicLinkIsRejected() throws {
        let parent = try project()
        let target = parent.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let link = parent.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(try VyronProjectGuidance.read(at: link)) {
            XCTAssertEqual($0 as? VyronProjectGuidanceError, .invalidRoot)
        }
    }
}
