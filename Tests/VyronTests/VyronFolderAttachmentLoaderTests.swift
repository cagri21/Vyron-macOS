import Darwin
import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronFolderAttachmentLoaderTests: XCTestCase {
    func testNestedFolderIncludesDeterministicInventoryAndText() async throws {
        let directory = try temporaryFolder()
        defer { cleanUp(directory) }
        try write("let value = 42", to: "Sources/Value.swift", in: directory)
        try write("# Read me", to: "README.md", in: directory)

        let loader = VyronFolderAttachmentLoader()
        let first = try await loader.load(directory)
        let second = try await loader.load(directory)

        XCTAssertEqual(first.name, directory.lastPathComponent)
        XCTAssertEqual(first.context, second.context)
        XCTAssertEqual(first.summary.includedFileCount, 2)
        XCTAssertEqual(first.summary.skippedFileCount, 0)
        XCTAssertFalse(first.summary.isLimited)
        XCTAssertTrue(first.context.contains("Sources/Value.swift"))
        XCTAssertTrue(first.context.contains("let value = 42"))
        XCTAssertLessThan(
            try XCTUnwrap(first.context.range(of: "README.md")?.lowerBound),
            try XCTUnwrap(first.context.range(of: "Sources/Value.swift")?.lowerBound)
        )
    }

    func testSensitiveHiddenAndGeneratedContentsAreNeverRead() async throws {
        let directory = try temporaryFolder()
        defer { cleanUp(directory) }
        for path in [".env", "credentials.json", "private.pem", ".hidden/note.txt", "node_modules/pkg/a.txt"] {
            try write("SENSITIVE_MARKER", to: path, in: directory)
        }
        try write("public content", to: "visible.txt", in: directory)

        let attachment = try await VyronFolderAttachmentLoader().load(directory)

        XCTAssertEqual(attachment.summary.includedFileCount, 1)
        XCTAssertEqual(attachment.summary.skippedFileCount, 3)
        XCTAssertFalse(attachment.context.contains("SENSITIVE_MARKER"))
        XCTAssertTrue(attachment.context.contains("Excluded directory contents"))
    }

    func testSymlinkedFilesAndDirectoriesAreNotFollowed() async throws {
        let directory = try temporaryFolder()
        let outside = try temporaryFolder()
        defer { cleanUp(directory); cleanUp(outside) }
        try write("OUTSIDE_MARKER", to: "outside.txt", in: outside)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("linked.txt"),
            withDestinationURL: outside.appendingPathComponent("outside.txt")
        )
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("linked-directory"), withDestinationURL: outside
        )

        let attachment = try await VyronFolderAttachmentLoader().load(directory)

        XCTAssertEqual(attachment.summary.includedFileCount, 0)
        XCTAssertFalse(attachment.context.contains("OUTSIDE_MARKER"))
        XCTAssertTrue(attachment.context.contains("symbolic link or special item"))
        do {
            _ = try await VyronFolderAttachmentLoader().load(directory.appendingPathComponent("linked-directory"))
            XCTFail("A symbolic link was accepted as a folder root.")
        } catch {
            XCTAssertTrue(error is VyronFolderAttachmentError)
        }
    }

    func testContextAndUTF8ExcerptsStayBoundedWithVisibleLimits() async throws {
        let directory = try temporaryFolder()
        defer { cleanUp(directory) }
        for index in 0..<12 {
            try write(String(repeating: "漢字🙂", count: 2_000), to: "\(index).txt", in: directory)
        }

        let attachment = try await VyronFolderAttachmentLoader().load(directory)

        XCTAssertLessThanOrEqual(attachment.context.utf8.count, VyronFolderAttachmentLimits.maximumContextBytes)
        XCTAssertTrue(attachment.summary.isLimited)
        XCTAssertGreaterThan(attachment.summary.includedFileCount, 0)
        XCTAssertGreaterThan(attachment.summary.skippedFileCount, 0)
        XCTAssertTrue(attachment.context.contains("[excerpt truncated]"))
        XCTAssertFalse(attachment.context.contains("�"))
    }

    func testBinaryInvalidUTF8AndOversizedFilesAreSkipped() async throws {
        let directory = try temporaryFolder()
        defer { cleanUp(directory) }
        try Data([0x00, 0x01]).write(to: directory.appendingPathComponent("binary.dat"))
        try Data([0xFF, 0xFE]).write(to: directory.appendingPathComponent("invalid.txt"))
        try Data(repeating: 0x61, count: VyronFolderAttachmentLimits.maximumFileBytes + 1)
            .write(to: directory.appendingPathComponent("large.txt"))

        let attachment = try await VyronFolderAttachmentLoader().load(directory)

        XCTAssertEqual(attachment.summary.includedFileCount, 0)
        XCTAssertEqual(attachment.summary.skippedFileCount, 3)
        XCTAssertTrue(attachment.context.contains("binary or invalid UTF-8"))
        XCTAssertTrue(attachment.context.contains("oversized or unavailable"))
    }

    func testEmptyFolderRemainsValidAndRootFileIsRejected() async throws {
        let directory = try temporaryFolder()
        defer { cleanUp(directory) }
        let empty = try await VyronFolderAttachmentLoader().load(directory)
        XCTAssertEqual(empty.summary.includedFileCount, 0)
        XCTAssertFalse(empty.summary.isLimited)
        try write("text", to: "file.txt", in: directory)

        do {
            _ = try await VyronFolderAttachmentLoader().load(directory.appendingPathComponent("file.txt"))
            XCTFail("A regular file was accepted as a folder.")
        } catch {
            XCTAssertTrue(error is VyronFolderAttachmentError)
        }
    }

    func testOversizedDirectoryStopsWithoutAnArbitrarySubset() async throws {
        let directory = try temporaryFolder()
        defer { cleanUp(directory) }
        for index in 0...VyronFolderAttachmentLimits.maximumEntries {
            try write("small", to: "\(index).txt", in: directory)
        }

        let attachment = try await VyronFolderAttachmentLoader().load(directory)

        XCTAssertTrue(attachment.summary.isLimited)
        XCTAssertEqual(attachment.summary.includedFileCount, 0)
        XCTAssertLessThanOrEqual(attachment.context.utf8.count, VyronFolderAttachmentLimits.maximumContextBytes)
    }

    func testCancellationDoesNotReturnAnAttachment() async throws {
        let directory = try temporaryFolder()
        defer { cleanUp(directory) }
        let loader = VyronFolderAttachmentLoader()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await loader.load(directory)
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled folder scan returned an attachment.")
        } catch is CancellationError {
            // Expected: cancellation remains distinct from a folder-read failure.
        }
    }

    func testDepthLimitDoesNotReadDeeperContentsOrBlockOnSpecialFiles() async throws {
        let directory = try temporaryFolder()
        defer { cleanUp(directory) }
        let deepPath = Array(repeating: "nested", count: VyronFolderAttachmentLimits.maximumDepth + 2)
            .joined(separator: "/") + "/deep.txt"
        try write("DEEP_MARKER", to: deepPath, in: directory)
        try write("safe", to: "visible.txt", in: directory)
        XCTAssertEqual(mkfifo(directory.appendingPathComponent("pipe").path, 0o600), 0)

        let attachment = try await VyronFolderAttachmentLoader().load(directory)

        XCTAssertTrue(attachment.summary.isLimited)
        XCTAssertEqual(attachment.summary.includedFileCount, 1)
        XCTAssertFalse(attachment.context.contains("DEEP_MARKER"))
        XCTAssertTrue(attachment.context.contains("directory not scanned: scan limit"))
        XCTAssertTrue(attachment.context.contains("symbolic link or special item"))
    }

    func testSymlinkInFolderAncestryIsRejected() async throws {
        let directory = try temporaryFolder()
        let outside = try temporaryFolder()
        defer { cleanUp(directory); cleanUp(outside) }
        try write("content", to: "nested/file.txt", in: outside)
        let link = directory.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        do {
            _ = try await VyronFolderAttachmentLoader().load(link.appendingPathComponent("nested"))
            XCTFail("A folder behind a user-created ancestry link was accepted.")
        } catch {
            XCTAssertTrue(error is VyronFolderAttachmentError)
        }
    }

    private func temporaryFolder() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("folder-attachment-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.resolvingSymlinksInPath()
    }

    private func write(_ text: String, to path: String, in directory: URL) throws {
        let file = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    private func cleanUp(_ directory: URL) {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            XCTFail("Could not remove the folder test fixture: \(error)")
        }
    }
}
