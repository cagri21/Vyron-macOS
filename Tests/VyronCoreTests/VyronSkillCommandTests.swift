import Foundation
import XCTest
@testable import VyronCore

final class VyronSkillCommandTests: XCTestCase {
    func testBuiltinCompactReservesItsAliasWithoutHidingAnInstalledSkill() throws {
        let root = try workspace()
        let compact = try skill(name: "compact", directory: root.appendingPathComponent("compact"))
        let commands = VyronSkillCommands(skills: [compact])

        XCTAssertEqual(commands.entries.map(\.name), ["codex-personal:compact"])
        XCTAssertTrue(commands.invoked(in: "/compact").isEmpty)
        XCTAssertEqual(commands.invoked(in: "/codex-personal:compact run").map(\.id), [compact.id])
    }

    func testUniqueSkillCommandsFilterByNameDescriptionAndPath() throws {
        let root = try workspace()
        let skill = try skill(name: "vyron", directory: root.appendingPathComponent("local-tools"))
        let commands = VyronSkillCommands(skills: [skill, skill])

        XCTAssertEqual(commands.entries.map(\.invocation), ["/vyron"])
        XCTAssertEqual(commands.matching(query: "/VYR").map(\.id), [skill.id])
        XCTAssertEqual(commands.matching(query: "test description").map(\.id), [skill.id])
        XCTAssertEqual(commands.matching(query: "local-tools").map(\.id), [skill.id])
        XCTAssertTrue(commands.matching(query: "missing").isEmpty)
    }

    func testDuplicateNamesHaveDeterministicDistinctAliases() throws {
        let root = try workspace()
        let first = try skill(name: "cleanup", directory: root.appendingPathComponent("first"))
        let second = try skill(name: "cleanup", directory: root.appendingPathComponent("second"))
        let third = try skill(name: "cleanup", directory: root.appendingPathComponent("third"), source: .claude)
        let commands = VyronSkillCommands(skills: [first, second, third])
        let reordered = VyronSkillCommands(skills: [third, second, first])

        XCTAssertEqual(commands.entries, reordered.entries)
        XCTAssertEqual(Set(commands.entries.map(\.name)).count, 3)
        XCTAssertTrue(commands.invoked(in: "/cleanup").isEmpty)
        for command in commands.entries {
            XCTAssertEqual(commands.invoked(in: command.invocation + " review").map(\.id), [command.id])
        }
    }

    func testPluginNamespaceKeepsNewestCachedDocumentAndOtherPackages() throws {
        let root = try workspace()
        let cache = root.appendingPathComponent("cache")
        let pluginRoot = VyronSkillRoot(directoryURL: cache, source: .codex, scope: .plugin)
        let old = try plugin(name: "use", root: pluginRoot, path: "vendor/figma/1.2.0/skills/use")
        let newest = try plugin(name: "use", root: pluginRoot, path: "vendor/figma/1.10.0/skills/use")
        let other = try plugin(name: "use", root: pluginRoot, path: "vendor/another/1.0/skills/use")
        let commands = VyronSkillCommands(skills: [old, newest, other])

        XCTAssertEqual(commands.entries.map(\.name), ["another:use", "figma:use"])
        XCTAssertEqual(commands.invoked(in: "/figma:use inspect").map(\.id), [newest.id])
    }

    func testOnlyExplicitCommandsActivateAndCodePathsBareNamesDoNot() throws {
        let root = try workspace()
        let skill = try skill(name: "vyron", directory: root.appendingPathComponent("vyron"))
        let commands = VyronSkillCommands(skills: [skill])

        XCTAssertEqual(commands.invoked(in: "/vyron run").map(\.id), [skill.id])
        XCTAssertEqual(commands.invoked(in: "Use $vyron to review").map(\.id), [skill.id])
        XCTAssertEqual(commands.invoked(in: "[$vyron](/local/SKILL.md)").map(\.id), [skill.id])
        XCTAssertEqual(commands.invoked(in: "/vyron\n$vyron").count, 1)
        for prompt in [
            "vyron run", "Open /vyron/file", "/vyron/file", "`$vyron`", "`/vyron`",
            "```swift\n/ vyron\n$vyron\n```", "~~~\n/vyron\n~~~", "prefix$vyron", "$vyron/path",
            "``$vyron``", "````\n```\n$vyron\n```\n````"
        ] {
            XCTAssertTrue(commands.invoked(in: prompt).isEmpty, prompt)
        }
        XCTAssertFalse(VyronSkillCommands.mightInvoke(in: "Read the local project"))
        XCTAssertTrue(VyronSkillCommands.mightInvoke(in: "/vyron run"))
    }

    func testContextLoadsFreshInstructionsAndIncludesSupportingDirectory() throws {
        let root = try workspace()
        let skill = try skill(name: "vyron", directory: root.appendingPathComponent("vyron"))
        let commands = VyronSkillCommands(skills: [skill])
        try "Fresh instructions".write(to: skill.fileURL, atomically: true, encoding: .utf8)

        let text = try XCTUnwrap(commands.context(for: "/vyron run"))

        XCTAssertTrue(text.contains("Fresh instructions"))
        XCTAssertTrue(text.contains(skill.fileURL.path))
        XCTAssertTrue(text.contains(skill.fileURL.deletingLastPathComponent().path))
        XCTAssertTrue(text.contains("read_skill_resource"))
        XCTAssertNil(try commands.context(for: "ordinary message"))
    }

    func testContextRefusesTruncatedOrReplacedSymlinkDocuments() throws {
        let root = try workspace()
        let skill = try skill(name: "vyron", directory: root.appendingPathComponent("vyron"))
        let commands = VyronSkillCommands(skills: [skill])
        try String(repeating: "a", count: 65_537).write(to: skill.fileURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try commands.context(for: "/vyron")) {
            XCTAssertEqual($0 as? VyronSkillActivationError, .truncatedDocument)
        }
        try FileManager.default.removeItem(at: skill.fileURL)
        let outside = root.appendingPathComponent("outside.md")
        try "Outside".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: skill.fileURL, withDestinationURL: outside)
        XCTAssertThrowsError(try commands.context(for: "/vyron")) {
            XCTAssertEqual($0 as? VyronSkillActivationError, .unavailableDocument)
        }
    }

    private func workspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("VyronSkillCommands-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    private func skill(
        name: String,
        directory: URL,
        source: VyronSkillSource = .codex
    ) throws -> VyronLocalSkill {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let content = "---\nname: \(name)\ndescription: Test description.\n---\nInstructions"
        let file = directory.appendingPathComponent("SKILL.md")
        try content.write(to: file, atomically: true, encoding: .utf8)
        return VyronLocalSkill(
            metadata: VyronSkillMetadata(name: name, description: "Test description."),
            root: VyronSkillRoot(directoryURL: directory, source: source, scope: .personal),
            fileURL: file,
            preview: VyronSkillPreview(content: content, isTruncated: false)
        )
    }

    private func plugin(name: String, root: VyronSkillRoot, path: String) throws -> VyronLocalSkill {
        let original = try skill(name: name, directory: root.directoryURL.appendingPathComponent(path))
        return VyronLocalSkill(metadata: original.metadata, root: root, fileURL: original.fileURL, preview: original.preview)
    }
}
