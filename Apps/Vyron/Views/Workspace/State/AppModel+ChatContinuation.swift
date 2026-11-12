import Foundation
import VyronCore

extension AppModel {
    func canContinueChat(_ id: UUID) -> Bool {
        guard chatActions(for: id)?.canContinue == true,
            let original = conversations.first(where: { $0.id == id }) else { return false }
        guard let path = original.workspacePath else { return true }
        let source = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        if let project = original.sidebarProjectPath, sidebarState.sidebarOrganization.contains(.project(project)),
            !sidebarProjectSourceFolders(project).contains(source.path) { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && workspaceState.developmentWorkspaces[source.resolvingSymlinksInPath().path] != nil
    }

    /// Continuing in another mode forks the transcript; the existing chat retains its fixed mode and history.
    @discardableResult
    func continueChat(_ id: UUID, in mode: ComposerMode) -> UUID? {
        guard mode == .chat || mode == .agent,
            chatActions(for: id)?.canContinue == true,
            let original = conversations.first(where: { $0.id == id }) else { return nil }
        guard let continued = Self.continuedChat(original, mode: mode) else { return nil }
        let taskFork: VyronDevelopmentTaskFork?
        do { taskFork = try prepareChatTaskFork(original, destination: continued) }
        catch {
            errorMessage = error.localizedDescription
            return nil
        }
        let previousOrganization = sidebarState.sidebarOrganization
        guard changeSidebar({ organization in
            organization.registerConversation(id: continued.id)
            if let folderID = organization.folderID(for: .conversation(id)) {
                try organization.move(.conversation(continued.id), to: folderID)
            }
        }) else { return nil }
        do { try taskFork?.save() }
        catch {
            undoChatTaskFork(taskFork, organization: previousOrganization, error: error.localizedDescription)
            return nil
        }
        let previousConversations = conversations
        conversations.insert(continued, at: 0)
        guard saveHistory() else {
            let historyError = errorMessage
            conversations = previousConversations
            undoChatTaskFork(taskFork, organization: previousOrganization, error: historyError)
            return nil
        }
        selectConversation(continued.id)
        return continued.id
    }

    private func prepareChatTaskFork(
        _ original: Conversation,
        destination: Conversation
    ) throws -> VyronDevelopmentTaskFork? {
        guard let path = original.workspacePath else { return nil }
        let canonicalPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let workspace = workspaceState.developmentWorkspaces[canonicalPath] else {
            throw LocalAIError.workspace(VyronStatusText.openProjectForEdits)
        }
        guard let context = VyronDevelopmentContinuationHistory.context(
            for: "continue", messages: original.messages + [ChatMessage(role: .user, content: "continue")]
        ) else { return nil }
        let taskMessages = VyronConversationCompactionCommand.taskHistory(destination.messages)
        let ownership = VyronConversationResponseOwnership(messages: taskMessages)
        guard let sourceID = context.priorResponseIDs.last,
            let destinationID = taskMessages.last(where: {
                $0.conversationRole == .assistant && !ownership.isChild($0)
            })?.id else { return nil }
        return try VyronDevelopmentTaskFork.prepare(
            workspace: workspace,
            source: VyronDevelopmentSessionContext(
                conversationID: original.id, responseID: sourceID, continuation: context
            ),
            destination: VyronDevelopmentSessionContext(conversationID: destination.id, responseID: destinationID)
        )
    }

    private func undoChatTaskFork(
        _ taskFork: VyronDevelopmentTaskFork?,
        organization: SidebarOrganization,
        error: String?
    ) {
        if changeSidebar({ $0 = organization }) { errorMessage = error }
        do { try taskFork?.removeCreatedCheckpoint() }
        catch { errorMessage = error.localizedDescription }
    }

    private static func continuedChat(_ original: Conversation, mode: ComposerMode) -> Conversation? {
        guard Set(original.messages.map(\.id)).count == original.messages.count else { return nil }
        var continued = Conversation(title: original.title, workspacePath: original.workspacePath)
        continued.projectPath = original.projectPath
        continued.mode = mode.rawValue
        let messageIDs = Dictionary(uniqueKeysWithValues: original.messages.map { ($0.id, UUID()) })
        continued.messages = original.messages.map { message in
            var copied = ChatMessage(
                id: messageIDs[message.id] ?? UUID(),
                role: message.role,
                content: message.content,
                activity: message.activity,
                suggestedQuestions: message.suggestedQuestions
            )
            copied.images = message.images
            copied.parentResponseID = message.parentResponseID.flatMap { messageIDs[$0] }
            return copied
        }
        if let originalContext = original.contextByMessageID {
            continued.contextByMessageID = originalContext.reduce(into: [:]) { context, entry in
                guard let oldID = UUID(uuidString: entry.key), let newID = messageIDs[oldID] else { return }
                context[newID.uuidString] = entry.value
            }
        }
        if let compaction = original.compaction, let boundary = messageIDs[compaction.throughMessageID] {
            continued.compaction = VyronConversationCompaction(
                summary: compaction.summary, throughMessageID: boundary, createdAt: compaction.createdAt
            )
        }
        return continued
    }
}
