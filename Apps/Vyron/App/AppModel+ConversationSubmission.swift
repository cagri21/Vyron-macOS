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
        let pdfs = composerAttachments.pdfs
        let files = composerAttachments.files
        let references = VyronConversationSubmissionReferences(
            folders: Self.folderAttachmentContext(folders), pdfs: pdfs, files: files
        )
        let referenceContext = references.context
        let prompt = enteredPrompt.isEmpty
            ? defaultAttachmentPrompt(references, includesImages: !images.isEmpty) : enteredPrompt
        let compactionCommand = VyronConversationCompactionCommand(prompt: prompt)
        if compactionCommand != nil, composerAttachments.hasDrafts {
            errorMessage = VyronCompactionText.attachments
            return nil
        }
        let compactedMemory = VyronConversationRequestContext.compactionReference(
            in: messages, snapshot: selectedConversation?.compaction
        )
        let systemPromptBytes = VyronConversationRequestContext.systemPrompt.utf8.count
        if !referenceContext.isEmpty,
            prompt.utf8.count + referenceContext.utf8.count + systemPromptBytes
                + VyronConversationLimits.folderSubmissionOverheadBytes
                + (compactedMemory?.content.utf8.count ?? 0)
                + images.count * VyronImageAttachment.estimatedContextTokens
                > VyronScreenshotLimits.maximumConversationBudget {
            if !files.isEmpty {
                errorMessage = VyronFolderAttachmentText.fileContextTooLarge
            } else {
                errorMessage = pdfs.isEmpty
                    ? VyronFolderAttachmentText.contextTooLarge : VyronFolderAttachmentText.pdfContextTooLarge
            }
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
            draft: .init(enteredPrompt: enteredPrompt, prompt: prompt, images: images, references: references),
            compaction: compaction,
            compactedMemory: compactedMemory
        )
    }

    private func defaultAttachmentPrompt(
        _ references: VyronConversationSubmissionReferences,
        includesImages: Bool
    ) -> String {
        if !references.files.isEmpty || (!references.pdfs.isEmpty && (includesImages || !references.folders.isEmpty))
            || (includesImages && !references.folders.isEmpty) {
            return VyronFolderAttachmentText.fileAnalysisPrompt
        }
        if !references.pdfs.isEmpty { return VyronFolderAttachmentText.pdfAnalysisPrompt }
        return references.folders.isEmpty ? VyronScreenshotText.analysisPrompt : VyronFolderAttachmentText.analysisPrompt
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
        if !submittedDraft.references.pdfs.isEmpty {
            userMessage.pdfPreviews = submittedDraft.references.pdfs.map(\.preview)
        }
        if !submittedDraft.references.files.isEmpty {
            userMessage.fileAttachments = submittedDraft.references.files.map(\.info)
        }
        composerAttachments.resetDrafts()
        conversations[index].messages.append(userMessage)
        let history = conversations[index].messages
        let linkedChatContext = linkedChatReferenceContext(in: submittedDraft.prompt)
        var previousContext = conversations[index].contextByMessageID ?? [:]
        let attachedContext = [submittedDraft.references.context, linkedChatContext]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: VyronTextSeparator.paragraph.rawValue)
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
