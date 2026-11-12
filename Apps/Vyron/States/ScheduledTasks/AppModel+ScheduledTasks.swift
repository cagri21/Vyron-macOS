import Foundation
import VyronCore
import VyronDevelopment

extension AppModel {
    var commandApprovalWorkspacePath: String? {
        if let generation = interactions.approvalGeneration,
            let owner = foregroundRun.response(forGeneration: generation), ownsInteractiveWorkResponse(owner) {
            return conversations.first { $0.id == owner.conversationID }?.workspacePath
        }
        if isRunningScheduledTask, let id = scheduledTasks.activeTaskID {
            return scheduledTasks.tasks.first { $0.id == id }?.definition.context.workspacePath
        }
        return workspaceState.workspaceURL?.path
    }

    func configureScheduledTasks() {
        scheduledTasks.configure(
            canRun: { [weak self] in
                guard let self else { return false }
                return !self.isShuttingDown && !self.foregroundRun.isGenerating && !self.isRunningScheduledTask
                    && !self.foregroundRun.hasBackgroundResponses
                    && !self.foregroundRun.isStoppingDevelopment && !self.computerWork.isComputerWorkActive && !self.computerWork.isPlanningControls
                    && !self.modelSelection.connectionOperationInProgress && !self.modelSelection.isStarting
                    && !self.modelDownloads.isActive
                    && !self.workspaceState.isLoadingWorkspace && !self.modelSelection.isRefreshing
                    && !self.voice.isActive
            },
            execute: { [weak self] task in
                guard let self else {
                    return VyronScheduledTaskRunResult(state: .stopped, conversationID: nil, detail: nil)
                }
                return await self.runScheduledTask(task)
            }
        )
    }

    func scheduledTaskContext() -> VyronScheduledTaskContext {
        let mode: VyronScheduledTaskMode
        switch composer.mode {
        case .agent: mode = .agent
        case .plan: mode = .plan
        case .chat: mode = .chat
        }
        return VyronScheduledTaskContext(
            workspacePath: workspaceState.workspaceURL?.path,
            mode: mode,
            model: VyronScheduledModelSelection(
                connectionID: modelSelection.activeConnectionID,
                model: modelSelection.selectedModel,
                automaticallySelect: modelSelection.isBuiltinConnection && modelSelection.automaticModelSelection,
                effort: composer.effort
            ),
            projectPath: workspaceState.selectedProjectPath ?? workspaceState.workspaceURL?.path
        )
    }

    func openScheduledTaskResult(_ id: UUID) {
        appNavigation.showScheduledTasks = false
        selectConversation(id)
    }

    private func scheduledProvider(_ selection: VyronScheduledModelSelection) throws -> any ModelProvider {
        guard let id = selection.connectionID else { return modelSelection.builtinClient }
        if id == modelSelection.activeConnectionID, let provider = modelSelection.configuredInferenceClient {
            return provider
        }
        guard let profile = modelSelection.connectionProfiles.first(where: { $0.id == id }) else {
            throw VyronScheduledExecutionError.connectionMissing
        }
        return try modelSelection.makeProvider(for: profile, apiKey: savedAPIKey(for: id))
    }

    private func runScheduledTask(_ task: VyronScheduledTask) async -> VyronScheduledTaskRunResult {
        guard !isShuttingDown, !Task.isCancelled, let runID = task.progress.lastRun?.id else {
            return VyronScheduledTaskRunResult(state: .stopped, conversationID: nil, detail: nil)
        }
        let context = task.definition.context
        if context.mode != .chat, let projectPath = context.projectPath,
            sidebarState.sidebarOrganization.contains(.project(projectPath)) {
            guard let workspacePath = context.workspacePath,
                sidebarProjectSourceFolders(projectPath).contains(where: {
                    URL(fileURLWithPath: $0).standardizedFileURL
                        == URL(fileURLWithPath: workspacePath).standardizedFileURL
                })
            else {
                return VyronScheduledTaskRunResult(
                    state: .failed, conversationID: nil, detail: VyronSidebarText.sourceFolderRemoved
                )
            }
        }
        isRunningScheduledTask = true
        defer {
            isRunningScheduledTask = false
            connectionBalances.responseCompleted(context.model.connectionID)
            refreshProject()
        }
        var conversation = Conversation(title: task.definition.title, workspacePath: context.workspacePath)
        conversation.projectPath = context.projectPath ?? context.workspacePath
        let mode: ComposerMode = context.mode == .agent ? .agent : context.mode == .plan ? .plan : .chat
        conversation.mode = mode.rawValue
        var activity = ResponseActivity()
        activity.record(VyronScheduledTaskText.preparingScheduled)
        let answer = ChatMessage(role: .assistant, content: "", activity: activity)
        conversation.messages = [ChatMessage(role: .user, content: task.definition.prompt), answer]
        let identity = VyronScheduledResponseIdentity(
            conversationID: conversation.id, messageID: answer.id, runID: runID
        )
        conversations.insert(conversation, at: 0)
        guard saveHistory() else {
            conversations.removeAll { $0.id == conversation.id }
            return VyronScheduledTaskRunResult(
                state: .failed, conversationID: nil, detail: VyronScheduledTaskText.historyUnavailable
            )
        }
        registerSidebarConversation(conversation.id)
        guard scheduledTasks.attachConversation(conversation.id, to: runID) else {
            return finishScheduledResponse(
                identity,
                content: VyronScheduledTaskText.storageSaveFailed,
                result: VyronScheduledTaskRunResult(
                    state: .failed, conversationID: conversation.id, detail: VyronScheduledTaskText.storageSaveFailed
                )
            )
        }
        do {
            try Task.checkCancellation()
            let provider = try scheduledProvider(context.model)
            let response: String
            if mode == .chat {
                let messages = try await scheduledChatMessages(task, identity: identity)
                var model = context.model.model
                if context.model.automaticallySelect && context.model.connectionID == nil {
                    let available = try await provider.models()
                    guard let selected = AgentModelRouter.selectModel(
                        from: available, preferredModel: model, effort: context.model.effort
                    ) else { throw VyronScheduledExecutionError.noAutomaticModel }
                    model = selected.name
                }
                try Task.checkCancellation()
                response = try await VyronChatInference.response(
                    using: provider,
                    request: VyronChatInferenceRequest(
                        model: model, messages: messages,
                        configuration: VyronChatInferenceConfiguration(
                            systemPrompt: VyronConversationRequestContext.systemPrompt, effort: context.model.effort
                        )
                    ),
                    onToken: { _ in }
                )
            } else {
                response = try await runScheduledDevelopment(task, provider: provider, identity: identity)
            }
            try Task.checkCancellation()
            let result = VyronScheduledTaskRunResult(
                state: .completed, conversationID: conversation.id, detail: VyronScheduledTaskText.completed
            )
            return finishScheduledResponse(identity, content: response, result: result)
        } catch {
            let stopped = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
            let detail = stopped ? VyronScheduledTaskText.stopped : VyronScheduledTaskErrorMessage.message(for: error)
            let result = VyronScheduledTaskRunResult(
                state: stopped ? .stopped : .failed, conversationID: conversation.id, detail: detail
            )
            return finishScheduledResponse(identity, content: detail, result: result)
        }
    }

    private func scheduledChatMessages(
        _ task: VyronScheduledTask,
        identity: VyronScheduledResponseIdentity
    ) async throws -> [ChatMessage] {
        guard let user = conversations.first(where: { $0.id == identity.conversationID })?.messages.first else {
            throw VyronScheduledExecutionError.historyUnavailable
        }
        guard let path = task.definition.context.workspacePath else { return [user] }
        let project = try ProjectWorkspace(rootURL: URL(fileURLWithPath: path, isDirectory: true))
        let inventory = try await project.contextSummary(maxFiles: VyronConversationLimits.maximumWorkspaceSummaryFiles)
        try Task.checkCancellation()
        let context = VyronConversationRequestContext.contextPrompt(workspaceContext: inventory, files: []).text
        let snapshots = [user.id.uuidString: context]
        if let index = conversations.firstIndex(where: { $0.id == identity.conversationID }) {
            conversations[index].contextByMessageID = snapshots
        }
        guard saveHistory() else { throw VyronScheduledExecutionError.historyUnavailable }
        return VyronConversationRequestContext.boundedHistory([user], context: snapshots).messages
    }

    private func runScheduledDevelopment(
        _ task: VyronScheduledTask,
        provider: any ModelProvider,
        identity: VyronScheduledResponseIdentity
    ) async throws -> String {
        let context = task.definition.context
        let report = scheduledModelFeatureReport(context.model)
        let feature: VyronModelFeature = context.mode == .agent ? .agent : .plan
        guard report[feature].isEnabled else {
            throw ModelProviderError.invalidSettings(
                VyronModelFeaturePresentation.reason(report[feature].reason)
                    ?? VyronAppText.modelFeaturesToolsUnsupported
            )
        }
        guard let path = context.workspacePath else { throw VyronScheduledExecutionError.projectRequired }
        let canonical = try ProjectWorkspace(rootURL: URL(fileURLWithPath: path, isDirectory: true)).rootURL
        let project: DevelopmentWorkspace
        if let existing = workspaceState.developmentWorkspaces[canonical.path] {
            project = existing
        } else {
            project = try DevelopmentWorkspace(rootURL: canonical)
            workspaceState.developmentWorkspaces[canonical.path] = project
        }
        let mode: ComposerMode = context.mode == .agent ? .agent : .plan
        let session = try mcpConnections.snapshot(mode: mode)
        let officeTools = VyronOfficeTools(
            workspace: project, configuration: VyronOfficePreferences.configuration()
        )
        let (events, continuation) = AsyncStream<VyronTrackedRunEvent>.makeStream()
        let consumer = Task { @MainActor [weak self] in
            for await event in events {
                switch event {
                case .development(let update):
                    self?.recordScheduledEvent(update, identity: identity)
                case .subagent(let update):
                    self?.recordSubagentEvent(
                        update, conversationID: identity.conversationID, messageID: identity.messageID
                    )
                }
            }
        }
        let result: DevelopmentResult
        do {
            let agent = DevelopmentAgent(
                client: provider,
                workspace: project,
                onSubagentEvent: { event in continuation.yield(.subagent(event)) }
            )
            try await agent.configureSession(VyronDevelopmentSessionContext(
                conversationID: identity.conversationID,
                responseID: identity.messageID
            ))
            result = try await agent.run(
                goal: task.definition.prompt,
                model: context.model.model,
                automaticModelSelection: context.model.automaticallySelect && context.model.connectionID == nil,
                effort: context.model.effort,
                mode: mode == .agent ? .agent : .plan,
                externalTools: session.tools + VyronOfficeTools.definitions,
                executeExternalTool: { [weak self] call in
                    guard let self else { throw CancellationError() }
                    if VyronOfficeTools.handles(call) {
                        return try await self.executeOfficeTool(call, tools: officeTools)
                    }
                    return try await self.executeScheduledTool(call, session: session)
                },
                onEvent: { event in continuation.yield(.development(event)) },
                approveCommand: { [weak self] approval in
                    guard let self else { return false }
                    return await self.reviewDevelopmentCommand(approval, generationID: identity.runID)
                }
            )
        } catch {
            continuation.finish()
            await consumer.value
            throw error
        }
        continuation.finish()
        await consumer.value
        guard result.isComplete else { throw DevelopmentError(result.finalMessage) }
        let commands = result.commands.map {
            "```\n$ \($0.command)\n\($0.output)\n[\($0.timedOut ? "timeout" : "exit \($0.exitCode)")]\n```"
        }.joined(separator: "\n\n")
        return result.finalMessage + (commands.isEmpty ? "" : "\n\n" + commands)
    }

    private func executeScheduledTool(
        _ call: DevelopmentToolCall,
        session: MCPToolSession
    ) async throws -> DevelopmentExternalResult {
        // The integration review is presented by the main content view.
        appNavigation.showScheduledTasks = false
        return try await mcpConnections.execute(call, session: session)
    }

    private func recordScheduledEvent(_ event: DevelopmentEvent, identity: VyronScheduledResponseIdentity) {
        recordDevelopmentActivity(
            event, conversationID: identity.conversationID, messageID: identity.messageID
        )
    }

    private func finishScheduledResponse(
        _ identity: VyronScheduledResponseIdentity,
        content: String,
        result: VyronScheduledTaskRunResult
    ) -> VyronScheduledTaskRunResult {
        guard let ci = conversations.firstIndex(where: { $0.id == identity.conversationID }),
            let mi = conversations[ci].messages.firstIndex(where: { $0.id == identity.messageID })
        else { return result }
        conversations[ci].messages[mi].content = content
        conversations[ci].messages[mi].activity?.record(result.detail ?? VyronScheduledTaskText.completed)
        conversations[ci].messages[mi].activity?.finish(
            result.state == .completed ? .completed : result.state == .stopped ? .stopped : .failed
        )
        conversations[ci].updatedAt = Date()
        if !saveHistory() {
            return VyronScheduledTaskRunResult(
                state: .failed, conversationID: result.conversationID, detail: VyronScheduledTaskText.storageSaveFailed
            )
        }
        return result
    }
}
