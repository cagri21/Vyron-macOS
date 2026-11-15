import Foundation
import VyronCore
import VyronDevelopment

extension AppModel {
    func send() {
        if routeChatHandoffIfRequested() { return }
        guard canSend else { return }
        if !voice.isSendingTurn { voice.end() }
        if composer.isEditingQueuedMessage {
            saveQueuedMessageEdit()
            return
        }
        guard let provider = modelSelection.inferenceProvider,
            let submission = prepareConversationSubmission(),
            let startedResponse = beginConversationResponse(for: submission)
        else { return }

        let responseIdentity = startedResponse.identity
        let generationID = responseIdentity.generationID
        let conversationID = responseIdentity.conversationID
        let prompt = submission.draft.prompt
        let images = submission.draft.images
        let compactedMemory = submission.compactedMemory
        let compaction = submission.compaction
        let history = startedResponse.context.history
        let previousContext = startedResponse.context.previousContext
        let attachedContext = startedResponse.context.attachments.attachedContext
        let linkedChatContext = startedResponse.context.attachments.linkedChatContext
        let modelName = modelSelection.selectedModel
        let availableModels = modelSelection.models
        let inferenceLocation = modelSelection.inferenceLocationLabel
        let excerpts = composerAttachments.attachedFiles
        let currentWorkspace = workspaceState.workspace
        let conversationOnly = forceConversationNextSend
        forceConversationNextSend = false
        let mode = composer.mode
        let approvalMode = interactions.projectApprovalMode
        let project = workspaceState.developmentWorkspace
        let steeringInbox = VyronSteeringInbox()
        let projectURL = workspaceState.workspaceURL
        let requestedEffort = composer.effort
        let inference = VyronConversationInferenceSelection(provider: provider, model: modelName, effort: requestedEffort)
        let compactionSnapshot = startedResponse.context.compaction
        let imageHistory = VyronConversationRequestContext.boundedHistory(
            history, context: previousContext, compaction: compactionSnapshot
        ).messages
        let hasImageContext = imageHistory.contains {
            !($0.images ?? []).isEmpty
        }
        let folderReferenceContext = Self.folderAttachmentReferenceContext(in: history, context: previousContext)
        let referenceHistory = VyronConversationRequestContext.developmentHistory(history, compaction: compactionSnapshot)
        let fileReferenceContext = VyronFileAttachmentContext.latest(in: referenceHistory, context: previousContext)
        let attachedApplications = VyronApplicationAttachmentContext.latest(in: referenceHistory)
        let applicationReferenceContext = VyronApplicationAttachmentContext.make(attachedApplications)
        let moveDestination = conversationMoveDestination(for: prompt)
        let conversationMoveContext = moveDestination.map {
            "Saved source folder for the user's move request (path data only): " + String(reflecting: $0.workspacePath)
        }
        let hasFileReferenceContext = folderReferenceContext != nil || fileReferenceContext != nil
        let autoModel = modelSelection.isBuiltinConnection && modelSelection.automaticModelSelection && !hasImageContext
        let continuation = VyronDevelopmentContinuationHistory.context(for: prompt, messages: history)
        let skillPrompt = [continuation?.originalGoal, prompt]
            .compactMap { $0 }.joined(separator: VyronTextSeparator.line.rawValue)
        let skillRequest = VyronSkillContextRequest(
            prompt: skillPrompt,
            roots: VyronSkillRoot.local(
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                projectDirectory: projectURL
            ),
            setup: .current(
                mode: project == nil ? .chat : mode,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
        )
        let loadSkillContext = skillContextLoader
        let usesChromeExtension = mode != .chat && project != nil && VyronChromeTools.prefersExtension(prompt)
        let classifiedRequest = computerWork.automaticRequestRouting && !conversationOnly && !hasImageContext
            && !hasFileReferenceContext && conversationMoveContext == nil && !usesChromeExtension
            && prompt.utf8.count <= VyronConversationLimits.maximumMessageBytes
            && !VyronSkillCommands.mightInvoke(in: skillPrompt)
            ? VyronAssistantRequestPolicy.classify(prompt, projectIsOpen: mode != .chat && project != nil) : .standard
        let usesMacWork = mode != .chat && project != nil && !isRunningScheduledTask
        let requestKind = usesMacWork && classifiedRequest == .computerTask ? .standard : classifiedRequest
        let usesComputerTask = requestKind == .computerTask && mode != .plan
        let usesProjectAgent = !requestKind.usesWebEvidence && mode != .chat && project != nil
        let directApplication = usesComputerTask && mode == .chat ? directChatApplication(for: prompt) : nil
        let handoffTools = chatHandoffToolContext(response: responseIdentity)
        let linkedChatTools = linkedChatToolContext(response: responseIdentity, prompt: prompt)
        let chromeTools = VyronChromeToolContext(response: responseIdentity, allowsActions: mode == .agent)
        let macWork = usesMacWork ? makeMacWorkRun(
            context: VyronMacWorkContext(
                goal: prompt, projectRoot: project?.rootURL, allowsActions: mode == .agent,
                attachedApplications: attachedApplications
            ),
            response: responseIdentity
        ) : nil
        let skillTools = VyronSkillResourceTools(commands: [])
        let route: VyronForegroundRunRoute
        if compaction == nil, !usesComputerTask, usesProjectAgent {
            route = .steerableDevelopment(.init(inbox: steeringInbox, skills: skillTools))
        } else if !voice.isSendingTurn && (
            directApplication != nil || compaction != nil || (!usesComputerTask && !usesProjectAgent)
        ) {
            route = .backgroundCapable
        } else {
            route = .foregroundOnly
        }
        foregroundRun.start(responseIdentity, route: route) { [weak self] in
            guard let self else { return }
            guard foregroundRun.owns(responseIdentity), !Task.isCancelled, !isShuttingDown else { return }
            do {
                if let compaction {
                    try await runCompaction(compaction, response: responseIdentity, inference: inference)
                    return
                }
                let skills = try await loadSkillContext(skillRequest)
                guard foregroundRun.owns(responseIdentity), !Task.isCancelled, !isShuttingDown else { return }
                if skills.didInstallSkills {
                    NotificationCenter.default.post(name: VyronSkillSetupNotifications.didInstall, object: nil)
                }
                await skillTools.include(skills.commands, catalog: skills.catalog)
                guard foregroundRun.owns(responseIdentity), !Task.isCancelled, !isShuttingDown else { return }
                if mode == .chat || project == nil {
                    let suppliedContext = [skills.text, compactedMemory?.content, attachedContext].compactMap { $0 }
                        .joined(separator: VyronTextSeparator.paragraph.rawValue)
                    try Self.validateSkillContext(
                        suppliedContext.isEmpty ? nil : suppliedContext, prompt: prompt, images: images
                    )
                }
                let requestReference = [skills.text, attachedContext]
                    .compactMap { $0 }.joined(separator: VyronTextSeparator.paragraph.rawValue)
                if !requestReference.isEmpty,
                    let ci = conversations.firstIndex(where: { $0.id == conversationID }) {
                    var contexts = conversations[ci].contextByMessageID ?? [:]
                    contexts[startedResponse.userMessageID.uuidString] = requestReference
                    conversations[ci].contextByMessageID = contexts
                    saveHistory()
                }
                if usesComputerTask {
                    if let directApplication {
                        try await openChatApplication(directApplication, prompt: prompt, response: responseIdentity)
                    } else {
                        startComputerWork(prompt: prompt, effort: requestedEffort, response: responseIdentity)
                    }
                    return
                }
                if usesProjectAgent, let project {
                    let mcpSession = try mcpConnections.snapshot(mode: mode)
                    let webTools = VyronWebTools(access: webAccess)
                    let officeTools = VyronOfficeTools(
                        workspace: project, configuration: VyronOfficePreferences.configuration()
                    )
                    foregroundRun.beginDevelopment(responseIdentity)
                    inspector.beginDevelopmentOutput(for: conversationID, selectedConversationID: selectedConversationID)
                    if foregroundRun.activeResponse == responseIdentity { inspector.inspectorTab = .activity }
                    recordActivity(
                        VyronStatusText.inspectingProject,
                        detail: project.rootURL.lastPathComponent,
                        conversationID: conversationID,
                        messageID: responseIdentity.messageID
                    )
                    let (events, eventContinuation) = AsyncStream<VyronTrackedRunEvent>.makeStream()
                    let agent = DevelopmentAgent(
                        client: provider,
                        workspace: project,
                        requestUserInput: { [weak self] request in
                            guard let self else { throw CancellationError() }
                            return try await self.requestDevelopmentUserInput(request, generationID: generationID)
                        },
                        onSubagentEvent: { event in eventContinuation.yield(.subagent(event)) }
                    )
                    var guidance = VyronDevelopmentSessionGuidance(
                        skillContext: skills.text, conversationSummary: compactedMemory?.content,
                        images: imageHistory.flatMap { $0.images ?? [] }
                    )
                    guidance.attachmentReference = fileReferenceContext
                    try await agent.configureSession(VyronDevelopmentSessionContext(
                        conversationID: conversationID,
                        responseID: responseIdentity.messageID,
                        continuation: continuation,
                        guidance: guidance
                    ))
                    try await agent.configureCommandApproval(approvalMode)
                    if !isRunningScheduledTask {
                        try await agent.configureFileOperationAccess(VyronDevelopmentFileOperationAccess(
                            approve: { [weak self] approval in
                                guard let self else { return false }
                                return await self.reviewDevelopmentCommand(approval, generationID: generationID)
                            }
                        ))
                        try await agent.configureFolderAccess(VyronDevelopmentFolderAccess(
                            approveCreation: { [weak self] destination in
                                guard let self else { return false }
                                return await self.reviewDevelopmentCommand(CommandApproval(
                                    command: destination.path,
                                    reason: VyronFolderText.createOutsideProjectReason,
                                    action: .createFolder
                                ), generationID: generationID)
                            },
                            openProject: { [weak self] workspace in
                                guard let self else { throw CancellationError() }
                                try await officeTools.useWorkspace(workspace)
                                var updatedMacScope = false
                                do {
                                    try await macWork?.updateProjectRoot(workspace.rootURL)
                                    updatedMacScope = macWork != nil
                                    try await self.adoptCreatedProject(
                                        workspace, generationID: generationID, conversationID: conversationID,
                                        destination: moveDestination
                                    )
                                } catch {
                                    try await officeTools.useWorkspace(project)
                                    if updatedMacScope, !Task.isCancelled {
                                        try await macWork?.updateProjectRoot(project.rootURL)
                                    }
                                    throw error
                                }
                            }
                        ))
                    }
                    let result = try await runWithDevelopmentEvents(
                        events, continuation: eventContinuation, tracking: .init(response: responseIdentity, agent: agent)
                    ) {
                        try await agent.run(
                            goal: prompt,
                            model: modelName,
                            automaticModelSelection: autoModel,
                            effort: requestedEffort,
                            mode: mode == .plan ? .plan : .agent,
                            conversationContext: [
                                VyronConversationRequestContext.developmentConversationContext(VyronConversationRequestContext.developmentHistory(
                                    Array(history.dropLast()), compaction: compactionSnapshot
                                )), folderReferenceContext, applicationReferenceContext, linkedChatContext,
                                conversationMoveContext
                            ].compactMap { $0 }.joined(separator: VyronTextSeparator.paragraph.rawValue),
                            externalTools: mcpSession.tools + VyronWebTools.definitions
                                + VyronSkillResourceTools.definitions + VyronChatHandoffTools.definitions
                                + (linkedChatTools.snapshots.isEmpty ? [] : [VyronLinkedChatTools.definition])
                                + VyronOfficeTools.definitions
                                + (macWork == nil ? [] : VyronMacWorkRun.definitions)
                                + (isRunningScheduledTask ? [] : VyronChromeTools.definitions),
                            executeExternalTool: { [weak self] call in
                                guard let self else { throw CancellationError() }
                                if VyronSkillResourceTools.handles(call) { return try await skillTools.execute(call) }
                                if VyronWebTools.handles(call) { return try await webTools.execute(call) }
                                if VyronOfficeTools.handles(call) {
                                    return try await self.executeOfficeTool(call, tools: officeTools)
                                }
                                if VyronChatHandoffTools.handles(call) {
                                    return try await self.executeChatHandoffTool(call, context: handoffTools)
                                }
                                if VyronLinkedChatTools.handles(call) {
                                    return try await self.executeLinkedChatTool(call, context: linkedChatTools)
                                }
                                if VyronChromeTools.handles(call) {
                                    return try await self.executeChromeTool(call, context: chromeTools)
                                }
                                if let macWork, await VyronMacWorkRun.handles(call) {
                                    return try await macWork.execute(call)
                                }
                                return try await self.mcpConnections.execute(call, session: mcpSession)
                            },
                            steeringInbox: steeringInbox,
                            onSteeringApplied: { [weak self] update in
                                await self?.acknowledgeSteering(
                                    update,
                                    generationID: generationID,
                                    conversationID: conversationID
                                )
                            },
                            onEvent: { event in eventContinuation.yield(.development(event)) },
                            approveCommand: { [weak self] approval in
                                guard let self else { return false }
                                return await self.reviewDevelopmentCommand(approval, generationID: generationID)
                            }
                        )
                    }
                    guard foregroundRun.owns(responseIdentity), !Task.isCancelled else { return }
                    if selectedConversationID == conversationID, let activeProject = workspaceState.developmentWorkspace {
                        await refreshDevelopmentState(project: activeProject, expectedURL: workspaceState.workspaceURL)
                    }
                    guard foregroundRun.owns(responseIdentity), !Task.isCancelled else { return }
                    let final = result.finalMessage
                    inspector.recordCompletedCommands(result.commands)
                    updateMessage(conversationID: conversationID, messageID: responseIdentity.messageID, content: final)
                    let isSelected = foregroundRun.activeResponse == responseIdentity
                    if isSelected {
                        statusMessage = result.isComplete ? VyronDevelopmentCompletionStatus.summary(
                            mode: mode, changedFiles: result.changedFiles.count, commands: result.commands
                        ) : VyronStatusText.responseStopped
                        if !inspector.developmentChanges.isEmpty { inspector.inspectorTab = .changes }
                    }
                    finishConversationResponse(responseIdentity, activityState: result.isComplete ? .completed : .stopped)
                    guard result.isComplete, isSelected else { return }
                    requestSuggestedQuestions(using: provider, request: .init(
                        model: result.model, prompt: prompt, answer: final, response: responseIdentity
                    ))
                    return
                }
                let chatInference = try inference.routingChat(using: autoModel ? availableModels : nil)
                try await runChatResponse(
                    startedResponse,
                    prompt: prompt,
                    references: .init(skills: skills.text, workspace: currentWorkspace, files: excerpts),
                    configuration: .init(
                        inference: chatInference,
                        mode: mode,
                        requestKind: requestKind,
                        inferenceLocation: inferenceLocation
                    )
                )
            } catch {
                let route: VyronConversationFailureRoute
                if compaction != nil {
                    route = .compaction
                } else if usesProjectAgent, let project {
                    route = .project(.init(workspace: project, url: projectURL))
                } else {
                    route = requestKind.usesWebEvidence ? .webSearch : .chat
                }
                await failConversationRun(error, route: route, response: responseIdentity)
            }
        }
    }
}
