import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronComposerSkillsModelTests: XCTestCase {
    func testQueryRecognizesOnlyLeadingSlashTokens() {
        XCTAssertEqual(VyronComposerSkillsModel.query(in: "/"), "")
        XCTAssertEqual(VyronComposerSkillsModel.query(in: "/compact"), "compact")
        XCTAssertEqual(VyronComposerSkillsModel.query(in: "  /vyron"), "vyron")
        XCTAssertEqual(VyronComposerSkillsModel.query(in: "/figma:figma-use"), "figma:figma-use")
        XCTAssertNil(VyronComposerSkillsModel.query(in: "use /vyron"))
        XCTAssertNil(VyronComposerSkillsModel.query(in: "/vyron build"))
        XCTAssertNil(VyronComposerSkillsModel.query(in: "/vyron "))
        XCTAssertNil(VyronComposerSkillsModel.query(in: "/Users/example/Project"))
        XCTAssertNil(VyronComposerSkillsModel.query(in: "https://example.com"))
        XCTAssertNil(VyronComposerSkillsModel.query(in: "`/vyron`"))
    }

    func testSearchKeyboardSelectionAndReplacementUseActualCommands() async throws {
        let inventory = inventory([skill("alpha"), skill("beta"), skill("vyron")])
        let library = VyronSkillsPresentation(loader: { _ in inventory })
        let model = VyronComposerSkillsModel(library: library)
        await model.load(projectDirectory: nil)
        model.updateDraft("/")
        XCTAssertTrue(model.isPresented)
        XCTAssertEqual(model.visibleCommands.map(\.name), ["compact", "side", "alpha", "beta", "vyron"])
        XCTAssertEqual(model.selectedCommand?.name, "compact")
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedCommand?.name, "side")
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedCommand?.name, "alpha")
        model.moveSelection(by: 100)
        XCTAssertEqual(model.selectedCommand?.name, "vyron")
        model.moveSelection(by: -100)
        XCTAssertEqual(model.selectedCommand?.name, "compact")

        model.updateDraft("  /vyr")
        let selected = try XCTUnwrap(model.selectedCommand)
        XCTAssertEqual(model.visibleCommands.map(\.name), ["vyron"])
        XCTAssertEqual(model.replacement(for: selected, in: "  /vyr"), "  /vyron ")
        XCTAssertNil(model.replacement(for: selected, in: "/vyron build"))
        model.updateDraft("/vyron build")
        XCTAssertFalse(model.isPresented)
        XCTAssertNil(model.selectedCommand)
    }

    func testSkillSelectionKeepsAnEditableTaskSeparateFromTheInvocation() async throws {
        let name = "vyron-refactor-indentation-swift"
        let inventory = inventory([skill("vyron"), skill(name)])
        let model = VyronComposerSkillsModel(library: VyronSkillsPresentation(loader: { _ in inventory }))
        await model.load(projectDirectory: nil)
        model.updateDraft("/vyron-refactor-indent")
        let command = try XCTUnwrap(model.selectedCommand)
        let selection = try XCTUnwrap(model.replacement(for: command, in: "/vyron-refactor-indent"))
        model.updateDraft(selection)
        XCTAssertFalse(model.isPresented)

        let selected = try XCTUnwrap(model.mention(in: selection))
        XCTAssertEqual(selected.label, "Vyron Refactor Indentation Swift")
        XCTAssertEqual(selected.text, "")
        let message = selected.prefix + "Indent this file\nKeep the comments"
        let reopened = try XCTUnwrap(model.mention(in: message))
        XCTAssertEqual(reopened.command, selected.command)
        XCTAssertEqual(reopened.text, "Indent this file\nKeep the comments")
        XCTAssertEqual(model.commands.invoked(in: message), [selected.command])

        XCTAssertNil(model.mention(in: "$vyron"))
        XCTAssertEqual(model.mention(in: "$" + name + " Review")?.command, selected.command)
        XCTAssertNil(model.mention(in: "/" + name))
        XCTAssertNil(model.mention(in: "$" + name + "/SKILL.md"))
        XCTAssertNil(model.mention(in: "/compact "))
    }

    func testBuiltInCommandsProvideInsertionTextWithoutInstalledSkills() throws {
        let model = VyronComposerSkillsModel()
        model.updateDraft("/")
        XCTAssertNil(model.inventory)
        XCTAssertTrue(model.commands.entries.isEmpty)
        XCTAssertEqual(model.visibleCommands.map(\.name), ["compact", "side"])
        let compact = try XCTUnwrap(model.selectedCommand)
        XCTAssertNil(compact.skill)
        XCTAssertEqual(compact.scopeLabel, VyronSkillText.commandLabel)
        XCTAssertEqual(compact.help, VyronSkillText.compactDescription)
        XCTAssertEqual(model.replacement(for: compact, in: "/"), "/compact ")
        model.updateDraft("/comp")
        XCTAssertEqual(model.selectedCommand?.name, "compact")
        model.updateDraft("/compact ")
        XCTAssertFalse(model.isPresented)

        model.updateDraft("/sid")
        let side = try XCTUnwrap(model.selectedCommand)
        XCTAssertEqual(side.name, "side")
        XCTAssertNil(side.skill)
        XCTAssertEqual(side.scopeLabel, VyronSkillText.commandLabel)
        XCTAssertEqual(model.replacement(for: side, in: "/sid"), "/side ")
        model.updateDraft("/side ")
        XCTAssertFalse(model.isPresented)
    }

    func testEscapeDismissalPersistsUntilDraftChangesAndEmptySearchHasNoSelection() async {
        let inventory = inventory([skill("vyron")])
        let model = VyronComposerSkillsModel(library: VyronSkillsPresentation(loader: { _ in inventory }))
        await model.load(projectDirectory: nil)
        model.updateDraft("/")
        model.dismiss()
        model.updateDraft("/")
        XCTAssertFalse(model.isPresented)
        model.updateDraft("/v")
        XCTAssertTrue(model.isPresented)
        model.updateDraft("/missing")
        XCTAssertTrue(model.isPresented)
        XCTAssertTrue(model.visibleCommands.isEmpty)
        XCTAssertNil(model.selectedCommand)
        model.moveSelection(by: 1)
        XCTAssertNil(model.selectedCommandID)
    }

    func testProjectChangeClearsCommandsAndIgnoresLateOrCanceledLoads() async {
        let loader = VyronSkillTestLoader()
        let library = VyronSkillsPresentation(loader: { try await loader.load($0) })
        let model = VyronComposerSkillsModel(library: library)
        model.updateDraft("/")
        let oldLoad = Task { await model.load(projectDirectory: URL(fileURLWithPath: "/old")) }
        await loader.waitForRequestCount(1)
        await loader.complete(0, result: .success(inventory([skill("old")])))
        await oldLoad.value
        XCTAssertEqual(model.visibleCommands.map(\.name), ["compact", "side", "old"])

        let refresh = Task { await model.load(projectDirectory: URL(fileURLWithPath: "/old")) }
        await loader.waitForRequestCount(2)
        let newLoad = Task { await model.load(projectDirectory: URL(fileURLWithPath: "/new")) }
        await loader.waitForRequestCount(3)
        XCTAssertTrue(model.isLoading)
        XCTAssertTrue(model.commands.entries.isEmpty)
        await loader.complete(1, result: .success(inventory([skill("late")])))
        await refresh.value
        XCTAssertTrue(model.commands.entries.isEmpty)
        newLoad.cancel()
        await loader.complete(2, result: .success(inventory([skill("canceled")])))
        await newLoad.value
        XCTAssertTrue(model.commands.entries.isEmpty)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.hasLoadError)
    }

    func testLoadFailureCanBeRefreshedAndRetried() async {
        let loader = VyronSkillTestLoader()
        let model = VyronComposerSkillsModel(library: VyronSkillsPresentation(loader: {
            try await loader.load($0)
        }))
        let load = Task { await model.load(projectDirectory: nil) }
        await loader.waitForRequestCount(1)
        await loader.complete(0, result: .failure(URLError(.cannotOpenFile)))
        await load.value
        XCTAssertTrue(model.hasLoadError)
        let refreshID = model.refreshID
        model.refresh()
        XCTAssertNotEqual(model.refreshID, refreshID)
        let retry = Task { await model.load(projectDirectory: nil) }
        await loader.waitForRequestCount(2)
        XCTAssertTrue(model.isLoading)
        XCTAssertFalse(model.hasLoadError)
        await loader.complete(1, result: .success(inventory([skill("recovered")])))
        await retry.value
        XCTAssertEqual(model.commands.entries.map(\.name), ["recovered"])
        XCTAssertFalse(model.isLoading)
    }

    private func inventory(_ skills: [VyronLocalSkill]) -> VyronSkillInventory {
        VyronSkillInventory(skills: skills, issues: [], didReachLimit: false)
    }

    private func skill(_ name: String) -> VyronLocalSkill {
        let root = VyronSkillRoot(
            directoryURL: URL(fileURLWithPath: "/skills"), source: .codex, scope: .personal
        )
        return VyronLocalSkill(
            metadata: VyronSkillMetadata(name: name, description: "Description for \(name)"),
            root: root,
            fileURL: root.directoryURL.appendingPathComponent("\(name)/SKILL.md"),
            preview: VyronSkillPreview(content: "# \(name)", isTruncated: false)
        )
    }
}
