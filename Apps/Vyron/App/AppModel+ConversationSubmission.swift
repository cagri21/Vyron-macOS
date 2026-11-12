import Foundation
import VyronCore

extension AppModel {
    var conversationDraftPrompt: String {
        let trimmed = composer.trimmedDraft
        return developmentTaskFilename(for: trimmed) == nil ? trimmed : composer.draft
    }

    func developmentTaskFilename(for prompt: String) -> String? {
        guard composer.mode != .chat, workspaceState.developmentWorkspace != nil else { return nil }
        return Self.projectTaskFilename(for: prompt)
    }

    static func projectTaskFilename(for prompt: String) -> String? {
        VyronDevelopmentTaskLimits.requiresTextAttachment(prompt) ? "task-description.txt" : nil
    }

    func conversationPromptLengthError(for prompt: String, fallback: @autoclosure () -> String) -> String? {
        let bytes = prompt.utf8.count
        guard bytes > VyronConversationLimits.maximumMessageBytes else { return nil }
        guard developmentTaskFilename(for: prompt) != nil else { return fallback() }
        let maximumBytes = VyronDevelopmentTaskLimits.maximumGoalBytes
        guard bytes > maximumBytes else { return nil }
        let kilobytes = (maximumBytes / 1_000).formatted(.number.locale(VyronResourceBundle.locale))
        return VyronStatusText.developmentTaskTooLarge(kilobytes)
    }

    func prepareConversationSubmission() -> VyronConversationSubmission? {
        let enteredPrompt = conversationDraftPrompt
        handoff.preparedChatHandoffDraft = nil
        let images = composerAttachments.screenshotDraft.images
        let folders = composerAttachments.folderAttachmentDraft.folders
        let folderContext = Self.folderAttachmentContext(folders)
        let prompt = enteredPrompt.isEmpty
            ? (folders.isEmpty ? VyronScreenshotText.analysisPrompt : VyronFolderAttachmentText.analysisPrompt)
            : enteredPrompt
        let compactionCommand = VyronConversationCompactionCommand(prompt: prompt)
        if compactionCommand != nil, composerAttachments.hasDrafts {
            errorMessage = VyronCompactionText.attachments
            return nil
        }
        let compactedMemory = VyronConversationRequestContext.compactionReference(
            in: messages, snapshot: selectedConversation?.compaction
        )
        let systemPromptBytes = VyronConversationRequestContext.systemPrompt.utf8.count
        if !folderContext.isEmpty,
            prompt.utf8.count + folderContext.utf8.count + systemPromptBytes
                + VyronConversationLimits.folderSubmissionOverheadBytes
                + (compactedMemory?.content.utf8.count ?? 0)
                + images.count * VyronImageAttachment.estimatedContextTokens
                > VyronScreenshotLimits.maximumConversationBudget {
            errorMessage = VyronFolderAttachmentText.contextTooLarge
            return nil
        }
        if compactionCommand == nil, let compactedMemory,
            prompt.utf8.count + compactedMemory.content.utf8.count + systemPromptBytes
                + VyronConversationLimits.compactedSubmissionOverheadBytes
                + images.count * VyronImageAttachment.estimatedContextTokens
                > VyronScreenshotLimits.maximumConversationBudget {
            errorMessage = VyronCompactionText.contextFull
            return nil
        }
        if !images.isEmpty,
            prompt.utf8.count + systemPromptBytes + VyronConversationLimits.messageOverheadBytes
                + images.count * VyronImageAttachment.estimatedContextTokens
                > VyronScreenshotLimits.maximumConversationBudget {
            errorMessage = VyronScreenshotText.promptTooLong
            return nil
        }
        if let lengthError = conversationPromptLengthError(for: prompt, fallback: VyronStatusText.messageTooLong) {
            errorMessage = lengthError
            return nil
        }
        if foregroundRun.isGenerating {
            queueDraft(prompt)
            return nil
        }
        let compaction: VyronConversationCompactionSubmission?
        do {
            compaction = try compactionCommand.map {
                try VyronConversationCompactionSubmission(command: $0, request: prepareCompaction($0))
            }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
        return VyronConversationSubmission(
            draft: .init(enteredPrompt: enteredPrompt, prompt: prompt, images: images, folderContext: folderContext),
            compaction: compaction,
            compactedMemory: compactedMemory
        )
    }

    func beginConversationResponse(for submission: VyronConversationSubmission) -> VyronStartedConversationResponse? {
        composer.cancelQueuedMessageDrain()
        followUpQuestions.cancel()
        let submittedDraft = submission.draft
        composer.draft = ""
        errorMessage = nil
        statusMessage = nil
        if selectedConversationID == nil {
            let title = initialConversationTitle(for: submittedDraft.prompt)
            var conversation = Conversation(title: title, workspacePath: workspaceState.workspaceURL?.path)
            conversation.projectPath = sidebarActiveProjectPath
            conversation.mode = composer.mode.rawValue
            conversations.insert(conversation, at: 0)
            selectedConversationID = conversation.id
            registerSidebarConversation(conversation.id)
        }
        guard let conversationID = selectedConversationID,
            let index = conversations.firstIndex(where: { $0.id == conversationID })
        else { return nil }
        let previousConversation = conversations[index]
        var userMessage = ChatMessage(role: .user, content: submittedDraft.prompt, images: submittedDraft.images)
        userMessage.developmentTaskFilename = developmentTaskFilename(for: submittedDraft.prompt)
        composerAttachments.resetDrafts()
        conversations[index].messages.append(userMessage)
        let history = conversations[index].messages
        let linkedChatContext = linkedChatReferenceContext(in: submittedDraft.prompt)
        var previousContext = conversations[index].contextByMessageID ?? [:]
        let attachedContext = [submittedDraft.folderContext.isEmpty ? nil : submittedDraft.folderContext, linkedChatContext]
            .compactMap { $0 }.joined(separator: VyronTextSeparator.paragraph.rawValue)
        if !attachedContext.isEmpty {
            previousContext[userMessage.id.uuidString] = attachedContext
            conversations[index].contextByMessageID = previousContext
        }
        var activity = ResponseActivity()
        activity.record(
            submission.compaction == nil ? VyronStatusText.preparingRequest : VyronCompactionText.preparing,
            detail: VyronStatusText.requestContext(
                composer.mode == .agent ? VyronWorkspaceText.agent
                    : composer.mode == .plan ? VyronWorkspaceText.plan : VyronWorkspaceText.chat,
                modelSelection.activeConnectionName,
                modelSelection.inferenceLocationLabel
            )
        )
        let assistant = ChatMessage(role: .assistant, content: "", activity: activity)
        conversations[index].messages.append(assistant)
        conversations[index].updatedAt = Date()
        conversations[index].mode = composer.mode.rawValue
        if !saveHistory(), submission.compaction != nil {
            conversations[index] = previousConversation
            composer.draft = submittedDraft.enteredPrompt
            return nil
        }

        let response = VyronResponseIdentity(
            generationID: UUID(), conversationID: conversationID, messageID: assistant.id
        )
        foregroundRun.begin(response, balanceConnectionID: modelSelection.activeConnectionID)
        return VyronStartedConversationResponse(
            identity: response,
            userMessageID: userMessage.id,
            context: .init(
                history: history,
                previousContext: previousContext,
                attachments: .init(attachedContext: attachedContext, linkedChatContext: linkedChatContext),
                compaction: previousConversation.compaction
            )
        )
    }
}
