import Darwin
import Foundation
import XCTest
@testable import VyronCore

final class VyronSkillDiscoveryTests: XCTestCase {
    func testLocalRootsKeepProvidersAndScopesAndIncludeSharedAndCachedSkills() {
        let roots = VyronSkillRoot.local(
            homeDirectory: URL(fileURLWithPath: "/Users/Example"),
            projectDirectory: URL(fileURLWithPath: "/Projects/Example")
        )

        XCTAssertEqual(roots.count, 9)
        XCTAssertEqual(roots.filter { $0.scope == .personal }.count, 4)
        XCTAssertEqual(roots.filter { $0.scope == .project }.count, 3)
        XCTAssertEqual(roots.filter { $0.scope == .plugin }.count, 2)
        XCTAssertTrue(roots.contains {
            $0.directoryURL.path == "/Users/Example/.codex/plugins/cache" && $0.source == .codex
        })
        XCTAssertTrue(roots.contains {
            $0.directoryURL.path == "/Projects/Example/.claude/skills" && $0.source == .claude
        })
        XCTAssertTrue(roots.contains {
            $0.directoryURL.path == "/Users/Example/Library/Application Support/VyronAI/Skills"
                && $0.source == .agents && $0.scope == .personal
        })
    }

    func testDiscoversPersonalProjectSystemAndCachedSkillDocumentsWithoutMergingNames() throws {
        let workspace = try workspace()
        let home = workspace.appendingPathComponent("home")
        let project = workspace.appendingPathComponent("project")
        try writeSkill(at: home.appendingPathComponent(".codex/skills/shared"), name: "same-name")
        try writeSkill(at: home.appendingPathComponent(".codex/skills/.system/tool"), name: "system-tool")
        try writeSkill(at: home.appendingPathComponent(".claude/skills/shared"), name: "same-name")
        try writeSkill(at: project.appendingPathComponent(".claude/skills/task"), name: "project-tool")
        try writeSkill(
            at: home.appendingPathComponent(".codex/plugins/cache/vendor/package/1.0/skills/nested"),
            name: "plugin-tool"
        )
        let roots = VyronSkillRoot.local(homeDirectory: home, projectDirectory: project)

        let result = try VyronSkillDiscovery().discover(in: roots)

        XCTAssertEqual(result.skills.count, 5)
        XCTAssertEqual(Set(result.skills.map(\.id)).count, 5)
        XCTAssertEqual(result.skills.filter { $0.name == "same-name" }.count, 2)
        XCTAssertEqual(result.skills.first { $0.name == "project-tool" }?.scope, .project)
        XCTAssertEqual(result.skills.first { $0.name == "plugin-tool" }?.scope, .plugin)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertFalse(result.didReachLimit)
        XCTAssertEqual(try VyronSkillDiscovery().discover(in: roots + roots).skills.count, 5)
    }

    func testMissingRootsProduceEmptyInventory() throws {
        let root = VyronSkillRoot(
            directoryURL: try workspace().appendingPathComponent("missing"),
            source: .claude,
            scope: .personal
        )

        let result = try VyronSkillDiscovery().discover(in: [root])

        XCTAssertTrue(result.skills.isEmpty)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertFalse(result.didReachLimit)
    }

    func testParsesQuotedFoldedAndLiteralMetadataAndPlainMarkdownFallback() throws {
        let workspace = try workspace()
        try writeDocument(
            "---\nname: 'actor''s-tool'\ndescription: >-\n  First line\n  second line.\n---\nBody",
            at: workspace,
            folder: "folded"
        )
        try writeDocument(
            "---\nname: \"Quoted tool\"\ndescription: |\n  First line\n  Second line\n---\nBody",
            at: workspace,
            folder: "literal"
        )
        try writeDocument("# Plain skill\n\nPlain description.\nMore body", at: workspace, folder: "plain")

        let result = try VyronSkillDiscovery().discover(in: [root(workspace)])

        XCTAssertEqual(result.skills.first { $0.name == "actor's-tool" }?.description, "First line second line.")
        XCTAssertEqual(result.skills.first { $0.name == "Quoted tool" }?.description, "First line\nSecond line")
        XCTAssertEqual(result.skills.first { $0.name == "plain" }?.description, "Plain description.")
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testMalformedMetadataAndInvalidEncodingDoNotHideOtherSkills() throws {
        let workspace = try workspace()
        try writeDocument("---\nname: \"Unclosed\ndescription: Broken\n---", at: workspace, folder: "broken")
        try writeDocument("---\nname: Missing boundary", at: workspace, folder: "boundary")
        let invalid = workspace.appendingPathComponent("invalid")
        try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
        try Data([0xFF]).write(to: invalid.appendingPathComponent("SKILL.md"))
        try writeSkill(at: workspace.appendingPathComponent("valid"), name: "valid")

        let result = try VyronSkillDiscovery().discover(in: [root(workspace)])

        XCTAssertEqual(result.skills.map(\.name), ["valid"])
        XCTAssertEqual(result.issues.filter { $0.reason == .malformedMetadata }.count, 2)
        XCTAssertEqual(result.issues.filter { $0.reason == .invalidEncoding }.count, 1)
    }

    func testAcceptsMultilineQuotedAndPlainDescriptionsWithTrailingComments() throws {
        let workspace = try workspace()
        try writeDocument(
            "---\nname: double\ndescription: \"First line\n  second line.\" # local comment\n---\nBody",
            at: workspace,
            folder: "double"
        )
        try writeDocument(
            "---\nname: single\ndescription: 'It''s a\n  multiline description.' # comment\n---\nBody",
            at: workspace,
            folder: "single"
        )
        try writeDocument(
            "---\nname: plain\ndescription: A plain description\n  with another line.\n---\nBody",
            at: workspace,
            folder: "plain"
        )

        let result = try VyronSkillDiscovery().discover(in: [root(workspace)])

        XCTAssertEqual(result.skills.first { $0.name == "double" }?.description, "First line second line.")
        XCTAssertEqual(result.skills.first { $0.name == "single" }?.description, "It's a multiline description.")
        XCTAssertEqual(
            result.skills.first { $0.name == "plain" }?.description,
            "A plain description with another line."
        )
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testSkipsSymlinkedRootsDirectoriesAndDocuments() throws {
        let workspace = try workspace()
        let outside = workspace.appendingPathComponent("outside")
        let scanned = workspace.appendingPathComponent("scanned")
        try writeSkill(at: outside, name: "outside")
        try FileManager.default.createDirectory(at: scanned, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: scanned.appendingPathComponent("linked-directory"),
            withDestinationURL: outside
        )
        try FileManager.default.createSymbolicLink(
            at: scanned.appendingPathComponent("SKILL.md"),
            withDestinationURL: outside.appendingPathComponent("SKILL.md")
        )
        let linkedRoot = workspace.appendingPathComponent("linked-root")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: outside)

        let result = try VyronSkillDiscovery().discover(in: [root(scanned), root(linkedRoot)])

        XCTAssertTrue(result.skills.isEmpty)
        XCTAssertEqual(result.issues.filter { $0.reason == .symbolicLink }.count, 3)
    }

    func testDoesNotReadNonRegularSkillFilesOrDocumentsOutsideSkillNames() throws {
        let workspace = try workspace()
        let fifo = workspace.appendingPathComponent("SKILL.md")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        try Data([0xFF]).write(to: workspace.appendingPathComponent("credentials.json"))
        try writeSkill(at: workspace.appendingPathComponent("valid"), name: "valid")

        let result = try VyronSkillDiscovery().discover(in: [root(workspace)])

        XCTAssertEqual(result.skills.map(\.name), ["valid"])
        XCTAssertEqual(result.issues.map(\.reason), [.nonRegularFile])
    }

    func testBoundedPreviewPreservesUTF8AndReportsTruncation() throws {
        let workspace = try workspace()
        let prefix = "---\nname: bounded\ndescription: Preview\n---\n"
        try writeDocument(prefix + String(repeating: "é", count: 100), at: workspace, folder: "bounded")
        let limit = prefix.utf8.count + 3
        let discovery = VyronSkillDiscovery(limits: VyronSkillDiscoveryLimits(maximumDocumentBytes: limit))

        let result = try discovery.discover(in: [root(workspace)])

        let skill = try XCTUnwrap(result.skills.first)
        XCTAssertEqual(skill.name, "bounded")
        XCTAssertTrue(skill.isContentTruncated)
        XCTAssertEqual(skill.content, prefix + "é")
        XCTAssertLessThanOrEqual(skill.content.utf8.count, limit)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testEntrySkillAndDepthLimitsReportPartialInventory() throws {
        let workspace = try workspace()
        try writeSkill(at: workspace.appendingPathComponent("first"), name: "first")
        try writeSkill(at: workspace.appendingPathComponent("second"), name: "second")
        let root = root(workspace)

        let entryLimited = try VyronSkillDiscovery(
            limits: VyronSkillDiscoveryLimits(maximumEntries: 1)
        ).discover(in: [root])
        let skillLimited = try VyronSkillDiscovery(
            limits: VyronSkillDiscoveryLimits(maximumSkills: 1)
        ).discover(in: [root])
        let depthLimited = try VyronSkillDiscovery(
            limits: VyronSkillDiscoveryLimits(maximumDepth: 1)
        ).discover(in: [root])

        XCTAssertTrue(entryLimited.didReachLimit)
        XCTAssertEqual(skillLimited.skills.count, 1)
        XCTAssertTrue(skillLimited.didReachLimit)
        XCTAssertTrue(depthLimited.skills.isEmpty)
        XCTAssertTrue(depthLimited.didReachLimit)
    }

    func testCancellationStopsDiscovery() async throws {
        let directory = try workspace()
        let root = root(directory)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try VyronSkillDiscovery().discover(in: [root])
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled discovery should throw")
        } catch is CancellationError {
            // Expected cancellation remains distinct from filesystem failures.
        }
    }

    private func workspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("VyronSkillTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    private func root(_ directory: URL) -> VyronSkillRoot {
        VyronSkillRoot(directoryURL: directory, source: .codex, scope: .personal)
    }

    private func writeSkill(at directory: URL, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: Test description.\n---\n\n# Instructions\n\nReference text."
            .write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    private func writeDocument(_ document: String, at directory: URL, folder: String) throws {
        let destination = directory.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try document.write(to: destination.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
}
