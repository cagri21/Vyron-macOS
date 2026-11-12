import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronWorkspaceToolsTests: XCTestCase {
    func testWorkToolsOpenRequestedInspectorWithoutAProjectAndClearActivity() throws {
        let model = try model()
        model.composer.mode = .agent
        model.workspaceState.workspaceURL = nil
        XCTAssertTrue(model.workspaceToolAvailability.projectToolsEnabled)

        for tool in [VyronWorkspaceTool.changes, .files] {
            model.appNavigation.showWorkspace = false
            model.appNavigation.trackingSelection = selection()

            model.openWorkspaceTool(tool)

            XCTAssertTrue(model.appNavigation.showWorkspace)
            XCTAssertNil(model.appNavigation.trackingSelection)
            XCTAssertEqual(model.inspector.inspectorTab, tool == .changes ? .changes : .files)
            XCTAssertNil(model.workspaceState.workspaceURL)
        }
    }

    func testTerminalTogglePreservesActivityDraftAndActiveResponse() throws {
        let model = try model()
        let activity = selection()
        let generation = UUID()
        model.composer.mode = .agent
        model.inspector.showTerminal = false
        model.appNavigation.trackingSelection = activity
        model.composer.draft = "Keep this unsent request"
        model.beginTestForegroundResponse(generationID: generation)

        model.openWorkspaceTool(.terminal)
        XCTAssertTrue(model.inspector.showTerminal)
        model.openWorkspaceTool(.terminal)

        XCTAssertFalse(model.inspector.showTerminal)
        XCTAssertEqual(model.appNavigation.trackingSelection, activity)
        XCTAssertEqual(model.composer.draft, "Keep this unsent request")
        XCTAssertTrue(model.foregroundRun.isGenerating)
        XCTAssertEqual(model.foregroundRun.activeGeneration, generation)
        model.foregroundRun.complete(generation)
    }

    func testChatCannotOpenProjectToolsOrAlterActivity() throws {
        let model = try model()
        let activity = selection()
        model.composer.mode = .chat
        model.appNavigation.showWorkspace = false
        model.inspector.showTerminal = false
        model.inspector.inspectorTab = .activity
        model.appNavigation.trackingSelection = activity
        XCTAssertFalse(model.workspaceToolAvailability.projectToolsEnabled)

        for tool in VyronWorkspaceTool.allCases {
            model.openWorkspaceTool(tool)
        }

        XCTAssertFalse(model.appNavigation.showWorkspace)
        XCTAssertFalse(model.inspector.showTerminal)
        XCTAssertEqual(model.inspector.inspectorTab, .activity)
        XCTAssertEqual(model.appNavigation.trackingSelection, activity)
        XCTAssertEqual(model.composer.mode, .chat)
    }

    func testAvailabilityDoesNotCreateSideChatsOrChangeSelectedConversation() throws {
        let model = try model()
        let selectedID = UUID()
        model.selectedConversationID = selectedID
        model.modelSelection.isConnected = false

        XCTAssertNil(model.workspaceToolAvailability.sideChatConversationID)
        model.composer.mode = .agent
        model.openWorkspaceTool(.files)
        model.openWorkspaceTool(.changes)
        model.openWorkspaceTool(.terminal)

        XCTAssertEqual(model.selectedConversationID, selectedID)
        XCTAssertTrue(model.newSideChatSessions.isEmpty)
        XCTAssertTrue(model.conversations.isEmpty)
    }

    private func selection() -> VyronTrackingSelection {
        VyronTrackingSelection(conversationID: UUID(), messageID: UUID(), subagentID: nil, entryID: nil)
    }

    private func model() throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronWorkspaceTools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return AppModel(historyDirectory: directory)
    }
}
