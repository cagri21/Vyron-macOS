import Foundation

extension AppModel {
    var composerSuggestion: VyronComposerSuggestion? {
        guard composer.draft.isEmpty, !foregroundRun.isGenerating, !computerWork.isComputerWorkActive, !isRunningScheduledTask,
            scheduledTasks.activeTaskID == nil, !isShuttingDown, !composer.isEditingQueuedMessage,
            !voice.isActive, !voice.isLiveConversation, !foregroundRun.isStoppingDevelopment,
            let answer = messages.last, answer.conversationRole == .assistant, answer.activity?.state == .completed,
            let question = answer.suggestedQuestions?.first,
            !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        return VyronComposerSuggestion(messageID: answer.id, text: question)
    }

    func acceptComposerSuggestion(_ suggestion: VyronComposerSuggestion) {
        guard composerSuggestion == suggestion else { return }
        useSuggestedQuestion(suggestion.text, messageID: suggestion.messageID)
    }
}
