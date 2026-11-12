import Foundation
import VyronCore

extension AppModel {
    var queuedMessages: [VyronQueuedMessage] { selectedConversation?.queuedMessages ?? [] }

    var canAcceptFollowUp: Bool {
        foregroundRun.isGenerating && foregroundRun.activeResponse?.conversationID == selectedConversationID
            && !isShuttingDown && !foregroundRun.isStoppingDevelopment && !computerWork.isComputerWorkActive
            && scheduledTasks.activeTaskID == nil
    }

    var canSteer: Bool {
        !composer.isEditingQueuedMessage && canAcceptConversationMessage
    }

    func canSteerQueuedMessage(_ message: VyronQueuedMessage) -> Bool {
        guard !composer.isEditingQueuedMessage else { return false }
        if VyronConversationCompactionCommand(prompt: message.content) != nil {
            return !foregroundRun.isGenerating && canAcceptCompactionCommand
        }
        return canAcceptConversationMessage
    }

    func queueDraft(_ prompt: String) {
        guard canAcceptFollowUp,
            let index = conversations.firstIndex(where: { $0.id == selectedConversationID })
        else { return }
        let message = VyronQueuedMessage(content: prompt)
        conversations[index].queuedMessages = (conversations[index].queuedMessages ?? []) + [message]
        composer.draft = ""
        saveHistory()
        if !composer.queueMessages { steerQueuedMessage(message.id) }
    }

    func editQueuedMessage(_ id: UUID) {
        guard !composer.isEditingQueuedMessage, !composer.pendingSteeringIDs.contains(id),
            let message = queuedMessages.first(where: { $0.id == id })
        else { return }
        composer.beginQueuedMessageEdit(message)
    }

    func saveQueuedMessageEdit() {
        guard let id = composer.editingQueuedMessageID else { return }
        let content = conversationDraftPrompt
        guard !content.isEmpty else { return }
        if let lengthError = conversationPromptLengthError(for: content, fallback: VyronQueueText.messageTooLong) {
            errorMessage = lengthError
            return
        }
        guard let ci = conversations.firstIndex(where: { $0.id == selectedConversationID }),
            let mi = conversations[ci].queuedMessages?.firstIndex(where: { $0.id == id })
        else {
            composer.cancelQueuedMessageEdit()
            return
        }
        conversations[ci].queuedMessages?[mi].content = content
        composer.cancelQueuedMessageEdit()
        errorMessage = nil
        saveHistory()
    }

    func deleteQueuedMessage(_ id: UUID) {
        // Once accepted by the running agent, an update cannot be retracted safely.
        guard !composer.pendingSteeringIDs.contains(id),
            let ci = conversations.firstIndex(where: { $0.id == selectedConversationID })
        else { return }
        if composer.editingQueuedMessageID == id { composer.cancelQueuedMessageEdit() }
        conversations[ci].queuedMessages?.removeAll { $0.id == id }
        saveHistory()
    }

    func steerQueuedMessage(_ id: UUID) {
        guard !composer.pendingSteeringIDs.contains(id),
            let message = queuedMessages.first(where: { $0.id == id }), canSteerQueuedMessage(message),
            let conversationID = selectedConversationID
        else { return }
        guard let response = foregroundRun.activeResponse else {
            sendQueuedMessage(message, conversationID: conversationID)
            return
        }
        guard response.conversationID == conversationID,
            VyronConversationCompactionCommand(prompt: message.content) == nil
        else { return }
        guard let steering = foregroundRun.steering(for: response) else {
            // Chat transports cannot accept live input. Preserve the partial reply and
            // continue from its history; no project command is running on this path.
            stopGeneration()
            sendQueuedMessage(message, conversationID: conversationID)
            if foregroundRun.isGenerating { statusMessage = VyronQueueText.chatSteering }
            return
        }
        let linkedChatContext = linkedChatReferenceContext(
            in: message.content, excludingConversationID: conversationID
        )
        steering.pendingMessageIDs.insert(id)
        synchronizePendingSteering(for: response)
        statusMessage = VyronQueueText.updatePending
        let request = VyronSkillContextRequest(
            prompt: message.content,
            roots: VyronSkillRoot.local(
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                projectDirectory: workspaceState.workspaceURL
            ),
            setup: .current(
                mode: composer.mode,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
        )
        let loadContext = skillContextLoader
        foregroundRun.enqueueSteering(generationID: response.generationID) { [weak self] in
            do {
                try Task.checkCancellation()
                guard self?.foregroundRun.owns(response) == true else { return }
                let skills = try await loadContext(request)
                guard let self, self.foregroundRun.owns(response), !Task.isCancelled else { return }
                if skills.didInstallSkills {
                    NotificationCenter.default.post(name: VyronSkillSetupNotifications.didInstall, object: nil)
                }
                await steering.skills.include(skills.commands, catalog: skills.catalog)
                guard self.foregroundRun.owns(response), !Task.isCancelled else { return }
                let reference = [skills.text, linkedChatContext].compactMap { $0 }.joined(separator: "\n\n")
                let content = [message.content, reference.isEmpty ? nil : reference]
                    .compactMap { $0 }.joined(separator: "\n\n")
                let accepted = await steering.inbox.append(VyronSteeringMessage(id: id, content: content))
                guard self.foregroundRun.owns(response) else { return }
                guard accepted else {
                    steering.pendingMessageIDs.remove(id)
                    self.synchronizePendingSteering(for: response)
                    return
                }
                if !reference.isEmpty,
                    let ci = self.conversations.firstIndex(where: { $0.id == conversationID }) {
                    var contexts = self.conversations[ci].contextByMessageID ?? [:]
                    contexts[id.uuidString] = reference
                    self.conversations[ci].contextByMessageID = contexts
                    self.saveHistory()
                }
            } catch {
                guard let self, self.foregroundRun.owns(response) else { return }
                steering.pendingMessageIDs.remove(id)
                self.synchronizePendingSteering(for: response)
                if self.selectedConversationID == response.conversationID,
                    self.foregroundRun.activeResponse == response, !(error is CancellationError) {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func acknowledgeSteering(_ update: VyronSteeringMessage, generationID: UUID, conversationID: UUID) {
        guard !Task.isCancelled,
            let response = foregroundRun.response(forGeneration: generationID),
            response.conversationID == conversationID,
            let steering = foregroundRun.steering(for: response), steering.pendingMessageIDs.contains(update.id),
            let ci = conversations.firstIndex(where: { $0.id == conversationID }),
            let message = conversations[ci].queuedMessages?.first(where: { $0.id == update.id }),
            let responseIndex = conversations[ci].messages.firstIndex(where: { $0.id == response.messageID })
        else { return }
        conversations[ci].queuedMessages?.removeAll { $0.id == update.id }
        steering.pendingMessageIDs.remove(update.id)
        synchronizePendingSteering(for: response)
        var userMessage = ChatMessage(id: message.id, role: .user, content: message.content)
        userMessage.developmentTaskFilename = Self.projectTaskFilename(for: message.content)
        conversations[ci].messages.insert(userMessage, at: responseIndex)
        conversations[ci].updatedAt = Date()
        saveHistory()
    }

    private func synchronizePendingSteering(for response: VyronResponseIdentity) {
        guard selectedConversationID == response.conversationID,
            foregroundRun.activeResponse == response
        else { return }
        composer.pendingSteeringIDs = foregroundRun.activePendingSteeringIDs
    }

    func stopQueuedMessageDelivery() {
        composer.cancelQueuedMessageDrain()
        composer.pendingSteeringIDs = []
    }

    func finishQueuedMessageRun(automaticallyContinue: Bool) {
        stopQueuedMessageDelivery()
        guard automaticallyContinue, let conversationID = selectedConversationID,
            !queuedMessages.isEmpty, !composer.isEditingQueuedMessage
        else { return }
        composer.queuedMessageDrainTask = Task { @MainActor [weak self] in
            // Let the completed response settle before starting the next queued turn.
            await Task.yield()
            guard let self, !Task.isCancelled, !self.foregroundRun.isGenerating,
                self.selectedConversationID == conversationID, !self.composer.isEditingQueuedMessage,
                let message = self.queuedMessages.first, self.canSteerQueuedMessage(message)
            else { return }
            self.composer.queuedMessageDrainTask = nil
            self.sendQueuedMessage(message, conversationID: conversationID)
        }
    }

    private func sendQueuedMessage(_ message: VyronQueuedMessage, conversationID: UUID) {
        guard !foregroundRun.isGenerating, canSteerQueuedMessage(message), selectedConversationID == conversationID,
            !composerAttachments.hasDrafts, !composerAttachments.isImporting,
            let ci = conversations.firstIndex(where: { $0.id == conversationID }),
            let position = conversations[ci].queuedMessages?.firstIndex(where: { $0.id == message.id })
        else { return }
        let previousDraft = composer.draft
        conversations[ci].queuedMessages?.remove(at: position)
        if isRedundantCompaction(message.content) {
            guard saveHistory() else {
                conversations[ci].queuedMessages?.insert(message, at: position)
                return
            }
            finishQueuedMessageRun(automaticallyContinue: true)
            return
        }
        composer.draft = message.content
        send()
        composer.draft = previousDraft
        if !foregroundRun.isGenerating {
            conversations[ci].queuedMessages?.insert(message, at: position)
        }
        saveHistory()
    }
}
