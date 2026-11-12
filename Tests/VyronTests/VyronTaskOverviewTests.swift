import Foundation
import XCTest
import VyronCore
import VyronDevelopment
@testable import Vyron

@MainActor
final class VyronTaskOverviewTests: XCTestCase {
    func testSourcesUseActualUserAttachmentsAndKeepStableUniqueIdentities() {
        let first = image("First.png")
        let second = image("Second.png")
        let assistantOnly = image("Not a user source.png")
        var conversation = Conversation(title: "Task", workspacePath: nil)
        var assistant = ChatMessage(role: "assistant", content: "Answer", activity: ResponseActivity())
        assistant.images = [assistantOnly]
        conversation.messages = [
            ChatMessage(role: "user", content: "Original request", images: [first]),
            assistant,
            ChatMessage(role: "user", content: "Follow up", images: [first, second]),
            ChatMessage(role: "assistant", content: "Latest legacy answer without activity")
        ]

        let snapshot = VyronTaskOverviewSnapshot(
            conversation: conversation, project: VyronTaskOverviewProject(path: nil, changes: [])
        )

        XCTAssertEqual(snapshot.sources.map(\.id), [first.id, second.id])
        XCTAssertNil(snapshot.response, "An older tracked response must not stand in for the latest legacy answer.")
        XCTAssertEqual(snapshot.conversationID, conversation.id)
    }

    func testResponseUsesTheOwningAssistantAfterVerifiedClarificationMessages() {
        var conversation = Conversation(title: "Task", workspacePath: nil)
        let response = ChatMessage(role: "assistant", content: "Answer", activity: ResponseActivity())
        var question = ChatMessage(role: "assistant", content: "Which color?")
        question.parentResponseID = response.id
        var answer = ChatMessage(role: "user", content: "Blue")
        answer.parentResponseID = response.id
        conversation.messages = [ChatMessage(role: "user", content: "Make the app"), question, answer, response]

        let snapshot = VyronTaskOverviewSnapshot(
            conversation: conversation, project: VyronTaskOverviewProject(path: nil, changes: [])
        )

        XCTAssertEqual(snapshot.response?.id, response.id)
    }

    func testOutputListUsesSavedNewFilesAndRetainsOtherChangesSeparately() throws {
        let added = try change(path: "Result.txt", before: nil, after: "Saved output")
        let edited = try change(path: "Existing.txt", before: "Before", after: "After")
        let project = VyronTaskOverviewProject(path: "/Projects/Example", changes: [added, edited])

        XCTAssertEqual(project.name, "Example")
        XCTAssertEqual(project.outputs.map(\.path), ["Result.txt"])
        XCTAssertEqual(project.changes.map(\.path), ["Result.txt", "Existing.txt"])
    }

    func testOverviewCannotExposeAnotherProjectsChangesAfterSelectionChanges() throws {
        let model = try model()
        var conversation = Conversation(title: "Other project", workspacePath: "/Projects/Other")
        conversation.mode = ComposerMode.agent.rawValue
        model.conversations = [conversation]
        model.selectedConversationID = conversation.id
        model.workspaceState.workspaceURL = URL(fileURLWithPath: "/Projects/Current")
        model.inspector.developmentChanges = [try change(path: "Private.txt", before: nil, after: "Other output")]

        let snapshot = model.taskOverview

        XCTAssertNil(snapshot.project.path)
        XCTAssertTrue(snapshot.project.changes.isEmpty)
        XCTAssertTrue(snapshot.project.outputs.isEmpty)
    }

    func testInspectorNavigationPreservesRunningTaskAndClearsOnlyActivitySelection() throws {
        let model = try model()
        var conversation = Conversation(title: "Task", workspacePath: "/Projects/Current")
        conversation.mode = ComposerMode.agent.rawValue
        let response = ChatMessage(role: "assistant", content: "Working", activity: ResponseActivity())
        conversation.messages = [response]
        model.conversations = [conversation]
        model.selectedConversationID = conversation.id
        model.workspaceState.workspaceURL = URL(fileURLWithPath: "/Projects/Current")
        model.appNavigation.trackingSelection = VyronTrackingSelection(
            conversationID: conversation.id, messageID: response.id, subagentID: nil, entryID: nil
        )
        let generation = UUID()
        model.beginTestForegroundResponse(generationID: generation)

        model.openOverviewInspector(.changes, context: model.taskOverview)

        XCTAssertTrue(model.appNavigation.showWorkspace)
        XCTAssertNil(model.appNavigation.trackingSelection)
        XCTAssertEqual(model.inspector.inspectorTab, .changes)
        XCTAssertTrue(model.foregroundRun.isGenerating)
        XCTAssertEqual(model.foregroundRun.activeGeneration, generation)
        model.foregroundRun.complete(generation)
    }

    func testStalePopoverCannotOpenInspectorOrActivityForAnotherChat() throws {
        let model = try model()
        var first = Conversation(title: "First", workspacePath: "/Projects/Current")
        first.mode = ComposerMode.agent.rawValue
        first.messages = [ChatMessage(role: "assistant", content: "First answer", activity: ResponseActivity())]
        var second = Conversation(title: "Second", workspacePath: "/Projects/Current")
        second.mode = ComposerMode.agent.rawValue
        model.conversations = [first, second]
        model.selectedConversationID = first.id
        model.workspaceState.workspaceURL = URL(fileURLWithPath: "/Projects/Current")
        let stale = model.taskOverview
        model.selectedConversationID = second.id
        model.appNavigation.showWorkspace = false
        model.inspector.inspectorTab = .files

        model.openOverviewInspector(.changes, context: stale)
        model.openOverviewActivity(stale)

        XCTAssertFalse(model.appNavigation.showWorkspace)
        XCTAssertEqual(model.inspector.inspectorTab, .files)
        XCTAssertNil(model.appNavigation.trackingSelection)
        XCTAssertEqual(model.selectedConversationID, second.id)
    }

    func testChatOverviewRetainsSourcesWithoutEnablingProjectTools() throws {
        let model = try model()
        var conversation = Conversation(title: "Chat", workspacePath: nil)
        conversation.mode = ComposerMode.chat.rawValue
        conversation.messages = [ChatMessage(role: "user", content: "Describe this", images: [image("Photo.png")])]
        model.conversations = [conversation]
        model.selectedConversationID = conversation.id
        model.composer.mode = .chat
        model.workspaceState.workspaceURL = URL(fileURLWithPath: "/Projects/Recent")
        model.appNavigation.showWorkspace = false
        let snapshot = model.taskOverview

        model.openOverviewInspector(.files, context: snapshot)

        XCTAssertNil(snapshot.project.path)
        XCTAssertEqual(snapshot.sources.count, 1)
        XCTAssertFalse(model.appNavigation.showWorkspace)
    }

    func testNewOutputOpensSavedChangeWhileFileInventoryIsStillRefreshing() throws {
        let model = try model()
        var conversation = Conversation(title: "Task", workspacePath: "/Projects/Current")
        conversation.mode = ComposerMode.agent.rawValue
        model.conversations = [conversation]
        model.selectedConversationID = conversation.id
        model.workspaceState.workspaceURL = URL(fileURLWithPath: "/Projects/Current")
        model.inspector.developmentChanges = [try change(path: "New.txt", before: nil, after: "New output")]
        model.inspector.developmentFiles = []
        model.appNavigation.showWorkspace = false

        model.openOverviewOutput("New.txt", context: model.taskOverview)

        XCTAssertTrue(model.appNavigation.showWorkspace)
        XCTAssertEqual(model.inspector.inspectorTab, .changes)
        XCTAssertEqual(model.inspector.selectedChangePath, "New.txt")
    }

    private func image(_ name: String) -> VyronImageAttachment {
        VyronImageAttachment(name: name, mimeType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47]))
    }

    private func change(path: String, before: String?, after: String) throws -> DevelopmentChange {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": UUID().uuidString, "path": path, "before": before as Any? ?? NSNull(),
            "after": after, "unifiedDiff": "Fixture diff"
        ])
        return try JSONDecoder().decode(DevelopmentChange.self, from: data)
    }

    private func model() throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronTaskOverview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return AppModel(historyDirectory: directory)
    }
}
