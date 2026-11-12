import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronSkillsPresentationTests: XCTestCase {
    func testSearchAndSourceFilterKeepDistinctSkillsWithMatchingNames() async {
        let codex = skill("Design", source: .codex)
        let claude = skill("Design", source: .claude)
        let shared = skill("Testing", source: .agents)
        let inventory = inventory([claude, shared, codex])
        let model = VyronSkillsPresentation(loader: { _ in inventory })
        await model.load(projectDirectory: nil)

        XCTAssertEqual(Set(model.visibleSkills.map(\.id)), Set([codex.id, claude.id, shared.id]))
        model.searchQuery = "  DESIGN\n"
        XCTAssertEqual(Set(model.visibleSkills.map(\.id)), Set([codex.id, claude.id]))
        model.filter = .claude
        XCTAssertEqual(model.visibleSkills, [claude])
        model.searchQuery = "does not exist"
        XCTAssertTrue(model.visibleSkills.isEmpty)
        model.searchQuery = ""
        model.filter = .shared
        XCTAssertEqual(model.visibleSkills, [shared])
    }

    func testSelectionAndQuerySurviveRefreshAndRemovedSelectionIsCleared() async {
        let loader = VyronSkillTestLoader()
        let model = VyronSkillsPresentation(loader: { try await loader.load($0) })
        let selected = skill("Selected", source: .codex)
        let first = Task { await model.load(projectDirectory: nil) }
        await loader.waitForRequestCount(1)
        XCTAssertTrue(model.isLoading)
        await loader.complete(0, result: .success(inventory([selected])))
        await first.value
        model.select(selected)
        model.searchQuery = "Selected"
        model.filter = .codex

        let second = Task { await model.load(projectDirectory: nil) }
        await loader.waitForRequestCount(2)
        await loader.complete(1, result: .success(inventory([selected])))
        await second.value
        XCTAssertEqual(model.selectedSkill?.id, selected.id)
        XCTAssertEqual(model.searchQuery, "Selected")
        XCTAssertEqual(model.filter, .codex)

        let third = Task { await model.load(projectDirectory: nil) }
        await loader.waitForRequestCount(3)
        await loader.complete(2, result: .success(inventory([])))
        await third.value
        XCTAssertNil(model.selectedSkillID)
        XCTAssertFalse(model.isLoading)
    }

    func testNewProjectClearsOldInventoryAndLateResponseCannotReplaceCurrentResult() async {
        let loader = VyronSkillTestLoader()
        let model = VyronSkillsPresentation(loader: { try await loader.load($0) })
        let oldSkill = skill("Old", source: .codex)
        let newSkill = skill("New", source: .claude)
        let oldLoad = Task { await model.load(projectDirectory: URL(fileURLWithPath: "/old")) }
        await loader.waitForRequestCount(1)
        await loader.complete(0, result: .success(inventory([oldSkill])))
        await oldLoad.value
        model.select(oldSkill)
        let oldRefresh = Task { await model.load(projectDirectory: URL(fileURLWithPath: "/old")) }
        await loader.waitForRequestCount(2)
        let newLoad = Task { await model.load(projectDirectory: URL(fileURLWithPath: "/new")) }
        await loader.waitForRequestCount(3)
        XCTAssertNil(model.inventory)
        XCTAssertNil(model.selectedSkillID)
        await loader.complete(1, result: .failure(URLError(.cannotOpenFile)))
        await oldRefresh.value
        XCTAssertTrue(model.isLoading)
        XCTAssertFalse(model.hasLoadError)
        await loader.complete(2, result: .success(inventory([newSkill])))
        await newLoad.value
        XCTAssertEqual(model.visibleSkills, [newSkill])
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.hasLoadError)
    }

    func testCanceledLoadCannotApplyLateResultOrDisplayFailure() async {
        let loader = VyronSkillTestLoader()
        let model = VyronSkillsPresentation(loader: { try await loader.load($0) })
        let load = Task { await model.load(projectDirectory: nil) }
        await loader.waitForRequestCount(1)
        load.cancel()
        await loader.complete(0, result: .success(inventory([skill("Canceled", source: .codex)])))
        await load.value
        XCTAssertNil(model.inventory)
        XCTAssertFalse(model.hasLoadError)
        XCTAssertFalse(model.isLoading)
    }

    func testFailureCanBeRetriedAndSuccessRestoresResults() async {
        let loader = VyronSkillTestLoader()
        let model = VyronSkillsPresentation(loader: { try await loader.load($0) })
        let first = Task { await model.load(projectDirectory: nil) }
        await loader.waitForRequestCount(1)
        await loader.complete(0, result: .failure(URLError(.cannotOpenFile)))
        await first.value
        XCTAssertTrue(model.hasLoadError)
        XCTAssertFalse(model.isLoading)
        let refreshID = model.refreshID
        model.refresh()
        XCTAssertNotEqual(model.refreshID, refreshID)

        let second = Task { await model.load(projectDirectory: nil) }
        await loader.waitForRequestCount(2)
        XCTAssertFalse(model.hasLoadError)
        let recovered = skill("Recovered", source: .codex)
        await loader.complete(1, result: .success(inventory([recovered])))
        await second.value
        XCTAssertEqual(model.visibleSkills, [recovered])
        XCTAssertFalse(model.hasLoadError)
        XCTAssertFalse(model.isLoading)
    }

    private func inventory(_ skills: [VyronLocalSkill]) -> VyronSkillInventory {
        VyronSkillInventory(skills: skills, issues: [], didReachLimit: false)
    }

    private func skill(_ name: String, source: VyronSkillSource) -> VyronLocalSkill {
        let root = VyronSkillRoot(
            directoryURL: URL(fileURLWithPath: "/skills/\(source)"),
            source: source,
            scope: .personal
        )
        return VyronLocalSkill(
            metadata: VyronSkillMetadata(name: name, description: "A description for \(name)"),
            root: root,
            fileURL: root.directoryURL.appendingPathComponent("\(name)/SKILL.md"),
            preview: VyronSkillPreview(content: "# \(name)", isTruncated: false)
        )
    }
}
