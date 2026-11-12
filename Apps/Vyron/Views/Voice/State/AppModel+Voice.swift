import Foundation

extension AppModel: VyronVoiceConversation {
    func validateVoiceStart(live: Bool) -> String? {
        guard !live || isConversationModeCompatible(.chat) else { return VyronWorkspaceText.modeLocked }
        guard !isShuttingDown, !foregroundRun.isGenerating, !computerWork.isComputerWorkActive, !foregroundRun.isStoppingDevelopment,
            !isRunningScheduledTask, !composer.isEditingQueuedMessage, scheduledTasks.activeTaskID == nil
        else { return VyronVoiceText.busy }
        guard !live || (composer.trimmedDraft.isEmpty && queuedMessages.isEmpty)
        else { return VyronVoiceText.draftRequired }
        guard !live || canAcceptConversationMessage(in: .chat) else { return VyronVoiceText.busy }
        voice.draftPrefix = composer.draft
        if live { composer.mode = .chat }
        return nil
    }

    func updateVoiceDraft(_ transcript: String) {
        guard !isShuttingDown, !foregroundRun.isGenerating, !isRunningScheduledTask else { return }
        let separator = voice.draftPrefix.isEmpty || voice.draftPrefix.last?.isWhitespace == true ? "" : " "
        composer.draft = voice.draftPrefix + (transcript.isEmpty ? "" : separator + transcript)
    }

    func sendVoiceTurn(_ transcript: String) -> Bool {
        guard composer.mode == .chat, !foregroundRun.isGenerating, !isShuttingDown,
            !isRunningScheduledTask, !computerWork.isComputerWorkActive, !foregroundRun.isStoppingDevelopment,
            !composer.isEditingQueuedMessage, composer.trimmedDraft.isEmpty,
            queuedMessages.isEmpty, canAcceptConversationMessage
        else { return false }
        composer.draft = transcript
        voice.isSendingTurn = true
        defer { voice.isSendingTurn = false }
        send()
        guard let activeGeneration = foregroundRun.activeGeneration else { return false }
        voice.generationID = foregroundRun.activeGeneration
        return true
    }

    func cancelVoiceTurn() {
        guard voice.generationID != nil else { return }
        stopGeneration()
    }
}
