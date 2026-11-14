import Foundation
import XCTest
import VyronDevelopment
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

    func testHistoricalChangeReviewSelectsExactFileWithoutOpeningProject() throws {
        let model = try model()
        let workspace = "/Projects/Archived"
        let conversation = Conversation(title: "Archived Work", workspacePath: workspace)
        let next = Conversation(title: "New chat", workspacePath: nil)
        model.conversations = [conversation, next]
        model.selectedConversationID = conversation.id
        let first = try change(path: "Sources/A.swift", before: nil, after: "let a = 1\n")
        let selected = try change(path: "Sources/B.swift", before: "let b = 1\n", after: "let b = 2\n")
        model.inspector.developmentChanges = [selected]
        model.inspector.selectedChangePath = selected.path
        model.appNavigation.trackingSelection = selection()

        model.showChangeReview(
            conversationID: conversation.id, workspacePath: workspace,
            changes: [first, selected], selectedPath: selected.path
        )

        XCTAssertTrue(model.isWorkspaceInspectorVisible)
        XCTAssertNil(model.appNavigation.trackingSelection)
        XCTAssertNil(model.workspaceState.workspaceURL)
        XCTAssertTrue(model.inspector.showsResponseChanges)
        XCTAssertEqual(model.inspector.inspectorTab, .changes)
        XCTAssertEqual(model.inspector.selectedReviewChange?.id, selected.id)
        model.inspector.selectChangeReviewPath(first.path)
        XCTAssertEqual(model.inspector.selectedReviewChange?.id, first.id)
        XCTAssertEqual(model.inspector.selectedChangePath, selected.path)

        model.selectedConversationID = next.id
        XCTAssertNil(model.inspector.responseChangeReview)
        model.showChangeReview(
            conversationID: conversation.id, workspacePath: workspace,
            changes: [first, selected], selectedPath: first.path
        )
        XCTAssertFalse(model.inspector.showsResponseChanges)
    }

    func testUnifiedDiffCountsOnlyChangedLinesAndKeepsSeparateHunks() throws {
        let middle = (1...12).map { "line \($0)\n" }.joined()
        let fixture = try change(
            path: "Example.swift",
            before: "first old\n" + middle + "last old",
            after: "first new\ninserted\n" + middle + "last new\n"
        )
        let diff = VyronUnifiedDiff(change: fixture)

        XCTAssertEqual(diff.addedCount, 3)
        XCTAssertEqual(diff.removedCount, 2)
        XCTAssertEqual(diff.lines.filter { $0.kind == .hunk }.map(\.text), ["@@ -1,4 +1,5 @@", "@@ -11,4 +12,4 @@"])
        XCTAssertEqual(diff.lines.first { $0.text == "last old" }?.oldNumber, 14)
        XCTAssertEqual(diff.lines.first { $0.text == "last new" }?.newNumber, 15)
        XCTAssertTrue(diff.unifiedText.contains("-last old\n\\ No newline at end of file\n+last new\n"))
        let preview = VyronUnifiedDiff(change: fixture, maximumLineCount: 3)
        XCTAssertEqual(preview.lines.count, 3)
        XCTAssertEqual(preview.addedCount, diff.addedCount)
        XCTAssertEqual(preview.removedCount, diff.removedCount)
    }

    private func change(path: String, before: String?, after: String) throws -> DevelopmentChange {
        var fields = ["id": UUID().uuidString, "path": path, "after": after, "unifiedDiff": ""]
        fields["before"] = before
        return try JSONDecoder().decode(DevelopmentChange.self, from: JSONEncoder().encode(fields))
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
