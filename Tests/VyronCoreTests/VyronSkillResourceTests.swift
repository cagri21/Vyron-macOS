import Darwin
import Foundation
import XCTest
@testable import VyronCore

@MainActor
final class VyronSkillResourceTests: XCTestCase {
    func testSelectedSkillCanReadRelativeReferenceAsText() async throws {
        let directory = try workspace()
        let command = command(directory: directory)
        let reference = directory.appendingPathComponent("references/development.md")
        try FileManager.default.createDirectory(at: reference.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Local reference instructions".write(to: reference, atomically: true, encoding: .utf8)
        let tools = VyronSkillResourceTools(commands: [command])

        let result = try await tools.execute(call(path: "references/development.md"))

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.text.contains("Local reference instructions"))
        XCTAssertTrue(VyronSkillResourceTools.definitions.allSatisfy(\.isReadOnly))
    }

    func testRejectsUnselectedSkillUnknownArgumentsAndUnknownTool() async throws {
        let directory = try workspace()
        try "Local".write(to: directory.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let tools = VyronSkillResourceTools(commands: [command(directory: directory)])
        let unselected = VyronSkillResourceTools(commands: [])
        let result = try await unselected.execute(call(path: "README.md"))
        XCTAssertTrue(result.isError)
        let unknownArgument = DevelopmentToolCall(name: "read_skill_resource", arguments: [
            "skill": .string("vyron"), "path": .string("README.md"), "extra": .bool(true)
        ])
        let unknown = try await tools.execute(unknownArgument)
        XCTAssertTrue(unknown.isError)
        let wrongName = try await tools.execute(DevelopmentToolCall(name: "read_file", arguments: [:]))
        XCTAssertTrue(wrongName.isError)
    }

    func testSteeringCanIncludeAnotherSelectedSkillAndRetainExistingSelection() async throws {
        let directory = try workspace()
        let first = directory.appendingPathComponent("first")
        let second = directory.appendingPathComponent("second")
        for folder in [first, second] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try folder.lastPathComponent.write(to: folder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        }
        let tools = VyronSkillResourceTools(commands: [command(directory: first)])
        await tools.include([command(directory: second, name: "review")])

        let original = try await tools.execute(call(path: "README.md"))
        let added = try await tools.execute(DevelopmentToolCall(name: "read_skill_resource", arguments: [
            "skill": .string("review"), "path": .string("README.md")
        ]))

        XCTAssertFalse(original.isError)
        XCTAssertTrue(original.text.contains("first"))
        XCTAssertFalse(added.isError)
        XCTAssertTrue(added.text.contains("second"))
    }

    func testReaderRejectsTraversalAbsoluteHiddenSymlinkBinaryAndNonregularFiles() throws {
        let directory = try workspace()
        let reader = VyronSkillResourceReader()
        let outside = directory.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".md")
        try "Outside".write(to: outside, atomically: true, encoding: .utf8)
        addTeardownBlock { try FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("link.md"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("linked"),
            withDestinationURL: outside.deletingLastPathComponent()
        )
        try Data([0x00, 0x41]).write(to: directory.appendingPathComponent("binary.txt"))
        try Data([0xFF]).write(to: directory.appendingPathComponent("invalid.txt"))
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("folder"), withIntermediateDirectories: true)
        XCTAssertEqual(mkfifo(directory.appendingPathComponent("pipe.md").path, 0o600), 0)

        for path in [
            "../" + outside.lastPathComponent, outside.path, ".env", "references/../SKILL.md", "./SKILL.md",
            "references//file.md", "link.md", "linked/" + outside.lastPathComponent,
            "binary.txt", "invalid.txt", "folder", "pipe.md"
        ] {
            XCTAssertThrowsError(try reader.read(relativePath: path, directory: directory), path)
        }
    }

    func testReaderRejectsOversizeAndSymlinkedSkillDirectory() throws {
        let directory = try workspace()
        try String(repeating: "a", count: 65_537)
            .write(to: directory.appendingPathComponent("large.md"), atomically: true, encoding: .utf8)
        let linked = directory.appendingPathComponent("linked-root")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: directory)
        let reader = VyronSkillResourceReader()

        XCTAssertThrowsError(try reader.read(relativePath: "large.md", directory: directory)) {
            XCTAssertEqual($0 as? VyronSkillActivationError, .truncatedDocument)
        }
        XCTAssertThrowsError(try reader.read(relativePath: "large.md", directory: linked))
    }

    func testCancellationRemainsDistinctFromReadFailure() async throws {
        let tools = VyronSkillResourceTools(commands: [])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await tools.execute(DevelopmentToolCall(name: "read_skill_resource", arguments: [:]))
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation must not be converted into an ordinary tool error.
        }
    }

    private func workspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("VyronSkillResources-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    private func command(directory: URL, name: String = "vyron") -> VyronSkillCommand {
        VyronSkillCommand(name: name, skill: VyronLocalSkill(
            metadata: VyronSkillMetadata(name: name, description: "Test"),
            root: VyronSkillRoot(directoryURL: directory, source: .codex, scope: .personal),
            fileURL: directory.appendingPathComponent("SKILL.md"),
            preview: VyronSkillPreview(content: "Instructions", isTruncated: false)
        ))
    }

    private func call(path: String) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "read_skill_resource", arguments: ["skill": .string("vyron"), "path": .string(path)])
    }
}
