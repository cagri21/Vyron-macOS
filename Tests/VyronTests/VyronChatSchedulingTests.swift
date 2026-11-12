import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronChatSchedulingTests: XCTestCase {
    func testDraftCapturesSelectedChatWithoutSavingOrChangingUnsentWork() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let original = chat([
            ChatMessage(role: "user", content: "Review this project every morning."),
            ChatMessage(role: "assistant", content: "Visible answer, never a replacement task.")
        ])
        install(original, in: test.model)
        XCTAssertTrue(test.model.saveHistory())
        test.model.composer.draft = "Unsent follow-up"
        test.model.composer.effort = .deep
        let context = test.model.scheduledTaskContext()
        let history = test.directory.appendingPathComponent("conversations.json")
        let originalData = try Data(contentsOf: history)
        let taskFile = test.directory.appendingPathComponent("scheduled-tasks.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: taskFile.path))

        let template = try XCTUnwrap(test.model.chatSchedulingTemplate(for: original.id))
        XCTAssertEqual(template.id, original.id)
        XCTAssertEqual(template.conversationID, original.id)
        XCTAssertEqual(template.definition.title, original.title)
        XCTAssertEqual(template.definition.prompt, original.messages[0].content)
        XCTAssertEqual(template.definition.context, context)
        XCTAssertEqual(test.model.selectedConversationID, original.id)
        XCTAssertEqual(test.model.composer.draft, "Unsent follow-up")
        XCTAssertEqual(try Data(contentsOf: history), originalData)
        XCTAssertTrue(test.model.scheduledTasks.tasks.isEmpty)
        XCTAssertNil(test.model.scheduledTasks.activeTaskID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: taskFile.path))

        var saves = 0
        _ = VyronScheduledTaskEditor(
            initial: nil,
            context: context,
            save: { _ in saves += 1; return true },
            template: template.definition
        )
        XCTAssertEqual(saves, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: taskFile.path))
    }

    func testUnselectedChatCanProduceDraftButUnknownDeletedAndArchivedChatsCannot() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let original = chat([ChatMessage(role: "user", content: "Summarize my project.")])
        install(original, in: test.model)
        XCTAssertNil(test.model.chatSchedulingTemplate(for: UUID()))
        test.model.selectedConversationID = UUID()
        XCTAssertNotNil(test.model.chatSchedulingTemplate(for: original.id))
        test.model.selectedConversationID = original.id
        test.model.conversations = []
        XCTAssertNil(test.model.chatSchedulingTemplate(for: original.id))
        install(original, in: test.model)
        XCTAssertTrue(test.model.changeSidebar { try $0.archiveConversations(ids: [original.id]) })
        XCTAssertNil(test.model.chatSchedulingTemplate(for: original.id))
    }

    func testUnselectedScheduleCapturesSavedModeSourceAndProjectWithoutChangingCurrentDraft() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = test.directory.appendingPathComponent("Saved source", isDirectory: true)
        let owner = test.directory.appendingPathComponent("Saved project", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        var original = chat([ChatMessage(role: "user", content: "Review the saved source every day")])
        original.workspacePath = source.path
        original.projectPath = owner.path
        original.mode = ComposerMode.agent.rawValue
        let current = chat([ChatMessage(role: "user", content: "Current unrelated chat")])
        test.model.conversations = [original, current]
        test.model.selectedConversationID = current.id
        test.model.composer.mode = .chat
        test.model.composer.draft = "Keep current draft"
        test.model.composer.effort = .deep
        XCTAssertTrue(test.model.changeSidebar {
            try $0.updateProject(path: owner.path, name: "Saved project", sourceFolders: [source.path])
            $0.registerConversation(id: original.id)
            $0.registerConversation(id: current.id)
        })
        let modelSelection = test.model.scheduledTaskContext().model

        let template = try XCTUnwrap(test.model.chatSchedulingTemplate(for: original.id))
        XCTAssertEqual(template.definition.context.mode, .agent)
        XCTAssertEqual(template.definition.context.workspacePath, source.path)
        XCTAssertEqual(template.definition.context.projectPath, owner.path)
        XCTAssertEqual(template.definition.context.model, modelSelection)
        XCTAssertEqual(template.definition.prompt, original.messages[0].content)
        XCTAssertEqual(test.model.selectedConversationID, current.id)
        XCTAssertEqual(test.model.composer.mode, .chat)
        XCTAssertEqual(test.model.composer.draft, "Keep current draft")
        XCTAssertNil(test.model.workspaceState.workspaceURL)
        XCTAssertTrue(test.model.scheduledTasks.tasks.isEmpty)

        test.model.conversations[0].mode = ComposerMode.plan.rawValue
        XCTAssertEqual(test.model.chatSchedulingTemplate(for: original.id)?.definition.context.mode, .plan)
        test.model.conversations[0].mode = ComposerMode.chat.rawValue
        XCTAssertEqual(test.model.chatSchedulingTemplate(for: original.id)?.definition.context.mode, .chat)
        test.model.conversations[0].mode = ComposerMode.agent.rawValue

        test.model.conversations[0].queuedMessages = [VyronQueuedMessage(content: "Pending source update")]
        XCTAssertNil(test.model.chatSchedulingTemplate(for: original.id))
        test.model.conversations[0].queuedMessages = nil
        XCTAssertTrue(test.model.changeSidebar {
            try $0.updateProject(path: owner.path, name: "Saved project", sourceFolders: [owner.path])
        })
        XCTAssertNil(test.model.chatSchedulingTemplate(for: original.id))
    }

    func testBusyOrLoadingConversationCannotProduceDraft() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let original = chat([ChatMessage(role: "user", content: "Check the project.")])
        install(original, in: test.model)
        XCTAssertNotNil(test.model.chatSchedulingTemplate(for: original.id))
        test.model.beginTestForegroundResponse()
        XCTAssertNil(test.model.chatSchedulingTemplate(for: original.id))
        test.model.foregroundRun.stop()
        test.model.workspaceState.isLoadingWorkspace = true
        XCTAssertNil(test.model.chatSchedulingTemplate(for: original.id))
        test.model.workspaceState.isLoadingWorkspace = false
        XCTAssertNotNil(test.model.chatSchedulingTemplate(for: original.id))
    }

    func testRepeatedContinueUsesRealOriginalGoalAndUserGuidance() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let goal = "Build the iOS app."
        var messages = [
            ChatMessage(role: "user", content: goal),
            ChatMessage(role: "user", content: "Keep the interface minimal."),
            ChatMessage(role: "assistant", content: "Assistant's invented next task must not become the prompt.")
        ]
        for text in ["Continue", "continıe", "Continue"] {
            messages.append(ChatMessage(role: "user", content: text))
            messages.append(ChatMessage(role: "assistant", content: "More visible progress."))
        }
        let original = chat(messages)
        install(original, in: test.model)
        let prompt = try XCTUnwrap(test.model.chatSchedulingTemplate(for: original.id)).definition.prompt
        XCTAssertEqual(prompt, goal + "\n\nKeep the interface minimal.")
        XCTAssertFalse(prompt.contains("Continue"))
        XCTAssertFalse(prompt.contains("Assistant"))
    }

    func testClarificationChildrenAndLaterSteeringRemainUserConstraints() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let response = ChatMessage(role: "assistant", content: "The first version is ready.")
        var question = ChatMessage(role: "assistant", content: "Which color?")
        question.parentResponseID = response.id
        var answer = ChatMessage(role: "user", content: "Which color?\nBlue")
        answer.parentResponseID = response.id
        let original = chat([
            ChatMessage(role: "user", content: "Create an iOS template app."),
            question, answer, response,
            ChatMessage(role: "user", content: "Continue"),
            ChatMessage(role: "user", content: "Use native controls."),
            ChatMessage(role: "assistant", content: "Continued.")
        ])
        install(original, in: test.model)
        let prompt = try XCTUnwrap(test.model.chatSchedulingTemplate(for: original.id)).definition.prompt
        XCTAssertEqual(prompt, "Create an iOS template app.\n\nWhich color?\nBlue\n\nUse native controls.")
    }

    func testNewSubstantiveTurnReplacesPreviousTaskAndItsConstraints() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let original = chat([
            ChatMessage(role: "user", content: "Build the old app."),
            ChatMessage(role: "user", content: "Use red."),
            ChatMessage(role: "assistant", content: "Old task response."),
            ChatMessage(role: "user", content: "Check the latest release notes."),
            ChatMessage(role: "user", content: "Keep the report short."),
            ChatMessage(role: "assistant", content: "Latest report.")
        ])
        install(original, in: test.model)
        let prompt = try XCTUnwrap(test.model.chatSchedulingTemplate(for: original.id)).definition.prompt
        XCTAssertEqual(prompt, "Check the latest release notes.\n\nKeep the report short.")
    }

    func testEmptyAssistantOnlyAndUnanchoredContinueHistoryAreUnavailable() {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        for messages in [
            [],
            [ChatMessage(role: "assistant", content: "Invented task.")],
            [ChatMessage(role: "user", content: "   ")],
            [ChatMessage(role: "user", content: "Continue"), ChatMessage(role: "assistant", content: "Done.")]
        ] {
            let original = chat(messages)
            install(original, in: test.model)
            XCTAssertNil(test.model.chatSchedulingTemplate(for: original.id))
        }
    }

    func testContextMustMatchSelectedConversationSourceAndProject() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = test.directory.appendingPathComponent("Source", isDirectory: true)
        let owner = test.directory.appendingPathComponent("Project", isDirectory: true)
        var original = chat([ChatMessage(role: "user", content: "Review the selected source folder.")])
        original.workspacePath = source.path
        original.projectPath = owner.path
        install(original, in: test.model)
        XCTAssertNil(test.model.chatSchedulingTemplate(for: original.id))
        test.model.workspaceState.workspaceURL = source
        test.model.workspaceState.selectedProjectPath = owner.path
        let template = try XCTUnwrap(test.model.chatSchedulingTemplate(for: original.id))
        XCTAssertEqual(template.definition.context.workspacePath, source.path)
        XCTAssertEqual(template.definition.context.projectPath, owner.path)
        test.model.workspaceState.selectedProjectPath = test.directory.appendingPathComponent("Other project").path
        XCTAssertNil(test.model.chatSchedulingTemplate(for: original.id))
        test.model.workspaceState.selectedProjectPath = owner.path
        test.model.workspaceState.workspaceURL = test.directory.appendingPathComponent("Other source")
        XCTAssertNil(test.model.chatSchedulingTemplate(for: original.id))
        test.model.workspaceState.workspaceURL = source
        test.model.conversations[0].mode = ComposerMode.agent.rawValue
        test.model.composer.mode = .agent
        XCTAssertEqual(test.model.composer.mode, .agent)
        XCTAssertNil(test.model.chatSchedulingTemplate(for: original.id), "Work requires its actual loaded workspace.")
        XCTAssertEqual(template.definition.context.workspacePath, source.path)
        XCTAssertEqual(template.definition.context.projectPath, owner.path)
    }

    private func chat(_ messages: [ChatMessage]) -> Conversation {
        var conversation = Conversation(title: "Selected task", workspacePath: nil)
        conversation.mode = ComposerMode.chat.rawValue
        conversation.messages = messages
        return conversation
    }

    private func install(_ conversation: Conversation, in model: AppModel) {
        model.conversations = [conversation]
        model.selectedConversationID = conversation.id
        model.registerSidebarConversation(conversation.id)
    }
}
