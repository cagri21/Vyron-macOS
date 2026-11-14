import Foundation

extension AppModel {
    var sideChatCommand: VyronSideChatCommand? {
        guard !composer.isEditingQueuedMessage else { return nil }
        return VyronSideChatCommand(prompt: composer.draft)
    }

    var canSubmitComposer: Bool {
        sideChatCommand == nil ? canSend : canSubmitSideChatCommand
    }

    var canSubmitSideChatCommand: Bool {
        guard sideChatCommand != nil, !isRunningScheduledTask, !voice.isActive,
            let sourceID = selectedConversationID
        else { return false }
        return canCreateTemporarySideChat(from: sourceID)
    }

    func submitComposer() -> UUID? {
        if sideChatCommand != nil { return submitSideChatCommand() }
        send()
        return nil
    }

    func submitSideChatCommand() -> UUID? {
        guard let command = sideChatCommand else { return nil }
        guard canSubmitSideChatCommand, let sourceID = selectedConversationID else {
            errorMessage = VyronToolsText.sideChatHint
            return nil
        }
        guard let sideID = newTemporarySideChat(from: sourceID),
            let session = newSideChatSessions[sideID]
        else { return nil }
        composer.draft = ""
        if errorMessage == VyronToolsText.sideChatHint { errorMessage = nil }
        if !command.question.isEmpty {
            session.draft = command.question
            session.send()
        }
        return sideID
    }
}
