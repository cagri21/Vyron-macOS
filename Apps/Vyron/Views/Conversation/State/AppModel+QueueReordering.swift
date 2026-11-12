import Foundation

extension AppModel {
    func canReorderQueuedMessage(_ id: UUID) -> Bool {
        guard let conversation = selectedConversation,
            let queue = conversation.queuedMessages, queue.count > 1
        else { return false }
        return !isShuttingDown && !foregroundRun.isStoppingDevelopment && !computerWork.isComputerWorkActive
            && !isRunningScheduledTask && scheduledTasks.activeTaskID == nil
            && !composer.isEditingQueuedMessage && !composer.pendingSteeringIDs.contains(id)
            && queue.contains { $0.id == id }
    }

    @discardableResult
    func moveQueuedMessage(_ id: UUID, to targetID: UUID, conversationID: UUID) -> Bool {
        guard selectedConversationID == conversationID, id != targetID,
            canReorderQueuedMessage(id), canReorderQueuedMessage(targetID),
            let conversationIndex = conversations.firstIndex(where: { $0.id == conversationID }),
            let originalQueue = conversations[conversationIndex].queuedMessages,
            let sourceIndex = originalQueue.firstIndex(where: { $0.id == id }),
            let targetIndex = originalQueue.firstIndex(where: { $0.id == targetID })
        else { return false }
        var reordered = originalQueue
        let message = reordered.remove(at: sourceIndex)
        reordered.insert(message, at: targetIndex)
        conversations[conversationIndex].queuedMessages = reordered
        guard saveHistory() else {
            conversations[conversationIndex].queuedMessages = originalQueue
            return false
        }
        return true
    }
}
