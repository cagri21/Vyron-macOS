import Foundation
import XCTest
@testable import VyronCore

@MainActor
final class VyronSkillCompanionTests: XCTestCase {
    func testLinkedCompanionDocumentEnablesItsSupportingFilesAndChainedReferences() async throws {
        let root = try workspace()
        let parent = try command(name: "parent", root: root, content: "[Child](../child/SKILL.md)")
        let child = try command(name: "child", root: root, content: "Child guide\n[Grandchild](../grandchild/SKILL.md)")
        let grandchild = try command(name: "grandchild", root: root, content: "Grandchild guide")
        try write("Supporting instructions", path: "references/development.md", command: child)
        let tools = VyronSkillResourceTools(commands: [parent], catalog: [parent, child, grandchild])

        let unavailable = try await tools.execute(call(skill: "child", path: "references/development.md"))
        XCTAssertTrue(unavailable.isError)
        let document = try await tools.execute(call(skill: "parent", path: "../child/SKILL.md"))
        XCTAssertFalse(document.isError)
        XCTAssertTrue(document.text.contains("Referenced skill: /child"))
        XCTAssertTrue(document.text.contains("Child guide"))
        let reference = try await tools.execute(call(skill: "child", path: "references/development.md"))
        XCTAssertFalse(reference.isError)
        XCTAssertTrue(reference.text.contains("Supporting instructions"))
        let chained = try await tools.execute(call(skill: "child", path: "../grandchild/SKILL.md"))
        XCTAssertFalse(chained.isError)
        XCTAssertTrue(chained.text.contains("Grandchild guide"))
    }

    func testKnownCompanionCannotBeReadThroughAnUnreferencedTraversal() async throws {
        let root = try workspace()
        let parent = try command(name: "parent", root: root, content: "[Child](../child/SKILL.md)")
        let child = try command(name: "child", root: root, content: "Child guide")
        try write("Private reference", path: "references/other.md", command: child)
        let tools = VyronSkillResourceTools(commands: [parent], catalog: [parent, child])

        for path in ["../child/references/other.md", "../child/./SKILL.md", "../child//SKILL.md"] {
            let result = try await tools.execute(call(skill: "parent", path: path))
            XCTAssertTrue(result.isError, path)
        }
    }

    func testReferencedFileMustBelongToKnownCatalogSkillAndNeverBeRemoteOrAbsolute() async throws {
        let root = try workspace()
        let parent = try command(name: "parent", root: root, content: """
        [Child](../child/SKILL.md)
        [Remote](https://example.com/../child/SKILL.md)
        [Absolute](\(root.path)/child/SKILL.md)
        """)
        let child = try command(name: "child", root: root, content: "Child guide")
        let tools = VyronSkillResourceTools(commands: [parent])

        for path in ["../child/SKILL.md", "https://example.com/../child/SKILL.md", child.skill.fileURL.path] {
            let result = try await tools.execute(call(skill: "parent", path: path))
            XCTAssertTrue(result.isError, path)
        }
        await tools.include([], catalog: [child])
        let nowKnown = try await tools.execute(call(skill: "parent", path: "../child/SKILL.md"))
        XCTAssertFalse(nowKnown.isError)
    }

    func testExactLinkedSupportingFileCanBeReadWithoutEnablingItsWholeSkill() async throws {
        let root = try workspace()
        let parent = try command(name: "parent", root: root, content: "[Reference](../child/references/guide.md)")
        let child = try command(name: "child", root: root, content: "Child guide")
        try write("Linked supporting text", path: "references/guide.md", command: child)
        let tools = VyronSkillResourceTools(commands: [parent], catalog: [parent, child])

        let linked = try await tools.execute(call(skill: "parent", path: "../child/references/guide.md"))
        XCTAssertFalse(linked.isError)
        XCTAssertTrue(linked.text.contains("Linked supporting text"))
        let unselected = try await tools.execute(call(skill: "child", path: "SKILL.md"))
        XCTAssertTrue(unselected.isError)
    }

    func testCompanionLinksAreCheckedAgainstFreshSourceDocument() async throws {
        let root = try workspace()
        let parent = try command(name: "parent", root: root, content: "[Child](../child/SKILL.md)")
        let child = try command(name: "child", root: root, content: "Child guide")
        let tools = VyronSkillResourceTools(commands: [parent], catalog: [parent, child])
        try "Removed link".write(to: parent.skill.fileURL, atomically: true, encoding: .utf8)

        let result = try await tools.execute(call(skill: "parent", path: "../child/SKILL.md"))

        XCTAssertTrue(result.isError)
    }

    func testLinkedSymlinkHiddenAndCredentialFilesRemainUnavailable() async throws {
        let root = try workspace()
        let parent = try command(name: "parent", root: root, content: """
        [Link](../child/linked.md)
        [Hidden](../child/.hidden)
        [Credentials](../child/credentials.json)
        """)
        let child = try command(name: "child", root: root, content: "Child guide")
        let childDirectory = child.skill.fileURL.deletingLastPathComponent()
        try write("Hidden", path: ".hidden", command: child)
        try write("Credentials", path: "credentials.json", command: child)
        try FileManager.default.createSymbolicLink(
            at: childDirectory.appendingPathComponent("linked.md"),
            withDestinationURL: parent.skill.fileURL
        )
        let tools = VyronSkillResourceTools(commands: [parent], catalog: [parent, child])

        for path in ["../child/linked.md", "../child/.hidden", "../child/credentials.json"] {
            let result = try await tools.execute(call(skill: "parent", path: path))
            XCTAssertTrue(result.isError, path)
        }
    }

    private func workspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("VyronSkillCompanions-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    private func command(name: String, root: URL, content: String) throws -> VyronSkillCommand {
        let directory = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("SKILL.md")
        try content.write(to: file, atomically: true, encoding: .utf8)
        return VyronSkillCommand(name: name, skill: VyronLocalSkill(
            metadata: VyronSkillMetadata(name: name, description: "Test"),
            root: VyronSkillRoot(directoryURL: root, source: .codex, scope: .personal),
            fileURL: file,
            preview: VyronSkillPreview(content: content, isTruncated: false)
        ))
    }

    private func write(_ content: String, path: String, command: VyronSkillCommand) throws {
        let file = command.skill.fileURL.deletingLastPathComponent().appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: file, atomically: true, encoding: .utf8)
    }

    private func call(skill: String, path: String) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "read_skill_resource", arguments: ["skill": .string(skill), "path": .string(path)])
    }
}
