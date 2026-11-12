import Foundation
import VyronCore

extension AppModel {
    func chatHandoffToolContext(response: VyronResponseIdentity) -> VyronChatHandoffToolContext {
        let projectPaths = sidebarState.sidebarOrganization.allProjects.sorted().prefix(50)
        let projects = projectPaths.enumerated().map { index, path in
            VyronChatHandoffToolProject(
                id: "project-\(index + 1)", path: path,
                name: VyronConversationRequestContext.bytePrefix(sidebarProjectName(path), limit: 160),
                sourceFolders: sidebarProjectSourceFolders(path)
            )
        }
        return VyronChatHandoffToolContext(response: response, projects: projects)
    }

    func executeChatHandoffTool(
        _ call: DevelopmentToolCall, context: VyronChatHandoffToolContext
    ) throws -> DevelopmentExternalResult {
        guard ownsInteractiveWorkResponse(context.response) else { throw CancellationError() }
        switch call.function.name {
        case VyronChatHandoffTools.list:
            guard Set(call.function.arguments.keys).isSubset(of: ["project_id"]) else {
                return handoffToolFailure("Unexpected arguments.")
            }
            guard call.function.arguments["project_id"] != nil else {
                return DevelopmentExternalResult(text: try encodedHandoffMetadata(context.projects.map {
                    ["project_id": $0.id, "name": $0.name]
                }))
            }
            guard let project = handoffToolProject(call, context: context) else {
                return handoffToolFailure("Choose a project_id returned by vyron_list_project_chats.")
            }
            let chats = handoffToolChats(project, sourceID: context.response.conversationID)
            return DevelopmentExternalResult(text: try encodedHandoffMetadata(chats.map {
                [
                    "conversation_id": $0.id.uuidString,
                    "title": VyronConversationRequestContext.bytePrefix($0.title, limit: 200)
                ]
            }))
        case VyronChatHandoffTools.prepare:
            guard selectedConversationID == context.response.conversationID,
                Set(call.function.arguments.keys).isSubset(of: ["project_id", "conversation_id", "request"]),
                let project = handoffToolProject(call, context: context),
                case .string(let request) = call.function.arguments["request"],
                !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                request.count <= VyronChatHandoffContext.maximumRequestCharacters,
                request.utf8.count <= VyronConversationLimits.maximumMessageBytes,
                !request.contains("\0"),
                let defaultSource = project.sourceFolders.first,
                project.path != selectedConversation?.sidebarProjectPath,
                (selectedConversation?.queuedMessages ?? []).isEmpty,
                composer.trimmedDraft.isEmpty
            else { return handoffToolFailure("A saved destination and a bounded request are required.") }
            let destinationID: UUID?
            let workspacePath: String
            if let argument = call.function.arguments["conversation_id"] {
                guard case .string(let value) = argument, let id = UUID(uuidString: value),
                    let chat = handoffToolChats(project, sourceID: context.response.conversationID).first(where: {
                        $0.id == id
                    }), let path = chat.workspacePath
                else { return handoffToolFailure("The destination chat is unavailable or busy.") }
                destinationID = id
                workspacePath = path
            } else {
                destinationID = nil
                workspacePath = defaultSource
            }
            let presentation = VyronChatHandoffPresentation(
                sourceID: context.response.conversationID, initialRequest: request,
                destination: VyronChatHandoffSelection(
                    projectPath: project.path, workspacePath: workspacePath, conversationID: destinationID
                )
            )
            handoff.pendingNativeChatHandoff = VyronPendingChatHandoff(response: context.response, presentation: presentation)
            return DevelopmentExternalResult(text:
                "Handoff chooser prepared. It will open after this response completes. "
                + "No request has been sent and no work has started in the destination."
            )
        default:
            return handoffToolFailure("This chat tool is unavailable.")
        }
    }

    func dismissPendingChatHandoff(generationID: UUID) {
        guard handoff.pendingNativeChatHandoff?.response.generationID == generationID else { return }
        handoff.pendingNativeChatHandoff = nil
    }

    @discardableResult
    func presentPendingChatHandoff(generationID: UUID, completed: Bool) -> Bool {
        guard let pending = handoff.pendingNativeChatHandoff,
            pending.response.generationID == generationID else { return false }
        handoff.pendingNativeChatHandoff = nil
        guard completed, !isShuttingDown, selectedConversationID == pending.response.conversationID,
            !sidebarState.sidebarOrganization.isConversationArchived(pending.response.conversationID),
            composer.trimmedDraft.isEmpty,
            (selectedConversation?.queuedMessages ?? []).isEmpty else { return false }
        handoff.chatHandoffPresentation = pending.presentation
        return true
    }

    private func handoffToolProject(
        _ call: DevelopmentToolCall, context: VyronChatHandoffToolContext
    ) -> VyronChatHandoffToolProject? {
        guard case .string(let id) = call.function.arguments["project_id"],
            let project = context.projects.first(where: { $0.id == id }),
            sidebarState.sidebarOrganization.contains(.project(project.path)),
            sidebarProjectSourceFolders(project.path) == project.sourceFolders else { return nil }
        return project
    }

    private func handoffToolChats(_ project: VyronChatHandoffToolProject, sourceID: UUID) -> [Conversation] {
        sidebarProjectConversations(project.path).filter {
            $0.id != sourceID && ($0.mode == nil || $0.mode == ComposerMode.agent.rawValue)
                && $0.workspacePath.map(project.sourceFolders.contains) == true
                && !sidebarState.sidebarOrganization.isConversationArchived($0.id)
                && !isSidebarConversationActive($0.id)
                && ($0.queuedMessages ?? []).isEmpty
        }.sorted { $0.updatedAt > $1.updatedAt }.prefix(40).map { $0 }
    }

    private func encodedHandoffMetadata(_ values: [[String: String]]) throws -> String {
        String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
    }

    private func handoffToolFailure(_ message: String) -> DevelopmentExternalResult {
        DevelopmentExternalResult(text: message, isError: true)
    }
}
