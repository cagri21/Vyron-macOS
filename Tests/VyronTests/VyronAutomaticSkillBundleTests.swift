import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronAutomaticSkillBundleTests: XCTestCase {
    func testBundledCatalogInstallsEveryRealPackageAndMakesResourcesReadable() async throws {
        let home = try temporaryHome()
        let current = VyronSkillSetupConfiguration.current(mode: .agent, homeDirectory: home)
        let locations = try XCTUnwrap(current.locations, "TrustedSkills must be included in the app resource bundle.")
        let catalog = try VyronSkillSetupCatalog.read(from: locations.catalogDirectory)
        XCTAssertEqual(Set(catalog.skills.map(\.identifier)), [
            "vyron-pdf", "vyron-documents", "vyron-spreadsheets", "vyron-presentations", "vyron-git"
        ])
        XCTAssertTrue(locations.installationDirectory.pathComponents.starts(with: home.pathComponents))
        let setup = VyronSkillSetupConfiguration(isEnabled: true, mode: .work, locations: locations)

        for entry in catalog.skills {
            let context = try await VyronSkillContextLoader.load(VyronSkillContextRequest(
                prompt: "/" + entry.identifier + " Complete the artifact task.",
                roots: [],
                setup: setup
            ))

            XCTAssertTrue(context.didInstallSkills, entry.identifier)
            let command = try XCTUnwrap(context.commands.first, entry.identifier)
            XCTAssertEqual(context.commands.count, 1, entry.identifier)
            XCTAssertEqual(command.name, entry.identifier)
            XCTAssertEqual(command.skill.name, entry.identifier)
            let source = locations.catalogDirectory.appendingPathComponent(entry.identifier)
                .appendingPathComponent("SKILL.md")
            let installed = locations.installationDirectory.appendingPathComponent(entry.identifier)
                .appendingPathComponent("SKILL.md")
            let sourceText = try String(contentsOf: source, encoding: .utf8)
            XCTAssertEqual(try String(contentsOf: installed, encoding: .utf8), sourceText)
            XCTAssertTrue(context.text?.contains(sourceText) == true)
            XCTAssertTrue(context.catalog.contains { $0.id == command.id })

            let tools = VyronSkillResourceTools(commands: context.commands, catalog: context.catalog)
            let resource = try await tools.execute(DevelopmentToolCall(name: "read_skill_resource", arguments: [
                "skill": .string(command.name), "path": .string("SKILL.md")
            ]))
            XCTAssertFalse(resource.isError, entry.identifier)
            XCTAssertTrue(resource.text.contains(sourceText), entry.identifier)
        }
    }

    func testGitSkillActivatesForCommitRequestsAndGitCommands() async throws {
        let home = try temporaryHome()
        let current = VyronSkillSetupConfiguration.current(mode: .agent, homeDirectory: home)
        let locations = try XCTUnwrap(current.locations)
        let setup = VyronSkillSetupConfiguration(isEnabled: true, mode: .work, locations: locations)

        let prompts = ["Commit these changes", "git status", "/git Show Git history", "/vyron-commit feature parser"]
        for (index, prompt) in prompts.enumerated() {
            let context = try await VyronSkillContextLoader.load(VyronSkillContextRequest(
                prompt: prompt, roots: [], setup: setup
            ))
            XCTAssertEqual(context.didInstallSkills, index == 0, prompt)
            XCTAssertEqual(context.commands.map(\.name), ["vyron-git"], prompt)
        }

        let noGit = try await VyronSkillContextLoader.load(VyronSkillContextRequest(
            prompt: "Don't commit these changes", roots: [], setup: setup
        ))
        XCTAssertTrue(noGit.commands.isEmpty)
    }

    private func temporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("VyronAutomaticSkillBundleTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: home) }
        return home
    }
}
