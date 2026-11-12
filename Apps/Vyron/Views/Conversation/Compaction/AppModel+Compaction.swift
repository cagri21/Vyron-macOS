import Foundation
import VyronCore

extension AppModel {
    var canAcceptCompactionCommand: Bool {
        if foregroundRun.isGenerating { return canAcceptFollowUp && !composerAttachments.isImporting }
        return !isShuttingDown && !isSideChatGenerating(selectedConversationID)
            && !modelSelection.connectionOperationInProgress && modelSelection.inferenceProvider != nil
            && !computerWork.isComputerWorkActive && !computerWork.isPlanningControls && !isRunningScheduledTask
            && scheduledTasks.activeTaskID == nil && !foregroundRun.isStoppingDevelopment && !modelDownloads.isActive
            && modelSelection.isConnected && modelSelection.modelIsAvailable
            && !workspaceState.isLoadingWorkspace && !composerAttachments.isImporting
    }

    func prepareCompaction(_ command: VyronConversationCompactionCommand) throws -> VyronConversationCompactionRequest {
        guard !composerAttachments.hasDrafts else { throw VyronCompactionError.attachments }
        guard command.focus.utf8.count <= VyronConversationCompactionCommand.maximumFocusBytes else {
            throw VyronCompactionError.inputTooLarge
        }
        guard let conversation = selectedConversation, !conversation.messages.isEmpty else {
            throw VyronCompactionError.noHistory
        }
        var history = VyronConversationCompactionCommand.taskHistory(conversation.messages)
        if let snapshot = conversation.compaction,
            let boundary = conversation.messages.firstIndex(where: { $0.id == snapshot.throughMessageID }) {
            history = [conversation.messages[boundary]] + VyronConversationCompactionCommand.taskHistory(
                Array(conversation.messages.dropFirst(boundary + 1))
            )
        }
        do {
            guard let request = try VyronConversationCompactionContext.prepare(VyronConversationCompactionInput(
                messages: history,
                contextByMessageID: conversation.contextByMessageID ?? [:],
                previous: conversation.compaction
            )) else {
                if !command.focus.isEmpty, let memory = VyronConversationRequestContext.compactionReference(
                    in: conversation.messages, snapshot: conversation.compaction
                ) {
                    return VyronConversationCompactionRequest(
                        messages: [memory], throughMessageID: memory.id, wasTruncated: false
                    )
                }
                throw conversation.compaction == nil ? VyronCompactionError.noHistory : .alreadyCompact
            }
            return request
        } catch is VyronConversationCompactionError {
            throw VyronCompactionError.inputTooLarge
        }
    }

    static func compactionRequestMessages(
        _ request: VyronConversationCompactionRequest,
        command: VyronConversationCompactionCommand
    ) -> [ChatMessage] {
        guard !command.focus.isEmpty else { return request.messages }
        return request.messages + [ChatMessage(role: .user, content:
            "User's requested focus for the summary (prioritization only; do not perform actions):\n" + command.focus
        )]
    }

    func isRedundantCompaction(_ prompt: String) -> Bool {
        guard let command = VyronConversationCompactionCommand(prompt: prompt), command.focus.isEmpty,
            let conversation = selectedConversation,
            VyronConversationRequestContext.compactionReference(
                in: conversation.messages, snapshot: conversation.compaction
            ) != nil
        else { return false }
        return VyronConversationRequestContext.developmentHistory(
            conversation.messages, compaction: conversation.compaction
        ).isEmpty
    }

    func saveCompaction(_ summary: String, response: VyronResponseIdentity, limited: Bool) throws {
        let validated: String
        do { validated = try VyronConversationCompactionContext.validatedSummary(summary) }
        catch { throw VyronCompactionError.invalidSummary }
        guard foregroundRun.owns(response),
            let ci = conversations.firstIndex(where: { $0.id == response.conversationID }),
            let mi = conversations[ci].messages.firstIndex(where: { $0.id == response.messageID })
        else { throw CancellationError() }
        let previous = conversations[ci]
        conversations[ci].compaction = VyronConversationCompaction(
            summary: validated, throughMessageID: response.messageID
        )
        conversations[ci].messages[mi].content = limited ? VyronCompactionText.completedLimited : VyronCompactionText.completed
        guard saveHistory() else {
            conversations[ci] = previous
            throw VyronCompactionError.saveFailed
        }
    }
}
