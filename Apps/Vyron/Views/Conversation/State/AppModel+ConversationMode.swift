import Foundation

extension AppModel {
    var isConversationModeLocked: Bool {
        messages.contains { $0.conversationRole == .user }
    }

    var isChatWorkspace: Bool { composer.mode == .chat }

    var restoredConversationMode: ComposerMode {
        selectedConversation?.mode.flatMap(ComposerMode.init(rawValue:)) ?? .agent
    }

    func isConversationModeCompatible(_ mode: ComposerMode) -> Bool {
        !isConversationModeLocked || (restoredConversationMode == .chat) == (mode == .chat)
    }

    func canSelectComposerMode(_ mode: ComposerMode) -> Bool {
        isConversationModeCompatible(mode) && isComposerModeAvailable(mode) && canRunInSelectedConversation(mode)
            && !isShuttingDown && !foregroundRun.isGenerating && !computerWork.isComputerWorkActive
            && !computerWork.isPlanningControls && !isRunningScheduledTask && scheduledTasks.activeTaskID == nil
            && !composer.isEditingQueuedMessage && !composerAttachments.isImporting
    }

    func selectComposerMode(_ mode: ComposerMode) {
        guard canSelectComposerMode(mode) else { return }
        composer.mode = mode
    }
}
