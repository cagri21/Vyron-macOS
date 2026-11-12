import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronWorkspaceInspectorTests: XCTestCase {
    func testClosingActivityInWorkDoesNotReplaceItWithTheFilePanel() throws {
        let model = try model()
        model.composer.mode = .agent
        model.appNavigation.showWorkspace = false
        model.appNavigation.trackingSelection = selection()
        XCTAssertTrue(model.isWorkspaceInspectorVisible)

        model.toggleWorkspaceInspector()

        XCTAssertFalse(model.isWorkspaceInspectorVisible)
        XCTAssertFalse(model.appNavigation.showWorkspace)
        XCTAssertNil(model.appNavigation.trackingSelection)
        model.toggleWorkspaceInspector()
        XCTAssertTrue(model.isWorkspaceInspectorVisible)
        XCTAssertTrue(model.appNavigation.showWorkspace)
    }

    func testChatCanCloseVisibleActivityWithoutEnablingProjectFiles() throws {
        let model = try model()
        model.composer.mode = .chat
        model.appNavigation.showWorkspace = true
        XCTAssertFalse(model.isWorkspaceInspectorVisible)
        XCTAssertFalse(model.canToggleWorkspaceInspector)
        model.appNavigation.trackingSelection = selection()
        XCTAssertTrue(model.canToggleWorkspaceInspector)
        XCTAssertTrue(model.isWorkspaceInspectorVisible)

        model.toggleWorkspaceInspector()

        XCTAssertNil(model.appNavigation.trackingSelection)
        XCTAssertFalse(model.isWorkspaceInspectorVisible)
        XCTAssertFalse(model.canToggleWorkspaceInspector)
        XCTAssertFalse(model.appNavigation.showWorkspace)
        model.toggleWorkspaceInspector()
        XCTAssertFalse(model.appNavigation.showWorkspace)
    }

    func testInspectorTogglePreservesRunningGenerationAndUnsentDraft() throws {
        let model = try model()
        let generation = UUID()
        model.composer.mode = .agent
        model.beginTestForegroundResponse(generationID: generation)
        model.composer.draft = "Keep this draft"
        model.appNavigation.showWorkspace = false

        model.toggleWorkspaceInspector()
        model.toggleWorkspaceInspector()

        XCTAssertTrue(model.foregroundRun.isGenerating)
        XCTAssertEqual(model.foregroundRun.activeGeneration, generation)
        XCTAssertEqual(model.composer.draft, "Keep this draft")
        XCTAssertFalse(model.appNavigation.showWorkspace)
        model.foregroundRun.complete(generation)
    }

    private func selection() -> VyronTrackingSelection {
        VyronTrackingSelection(conversationID: UUID(), messageID: UUID(), subagentID: nil, entryID: nil)
    }

    private func model() throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronWorkspaceInspector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return AppModel(historyDirectory: directory)
    }
}
