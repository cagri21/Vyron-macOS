import Foundation
import VyronCore

extension AppModel {
    var canManageMCPConnections: Bool {
        !isShuttingDown && !foregroundRun.isGenerating && !foregroundRun.isStoppingDevelopment
            && foregroundRun.developmentResponse == nil
    }

    var selectedCommandApproval: CommandApproval? {
        guard interactions.showCommandApproval,
            let generation = interactions.approvalGeneration,
            canPresentCommandApproval(generation) else { return nil }
        return interactions.pendingCommandApproval
    }

    var selectedCommandApprovalWorkspacePath: String? {
        selectedCommandApproval == nil ? nil : commandApprovalWorkspacePath
    }

    var selectedCommandApprovalConversationTitle: String? {
        guard selectedCommandApproval != nil else { return nil }
        return commandApprovalConversation?.title
    }

    private var commandApprovalConversation: Conversation? {
        guard let owner = notificationCommandOwner else { return nil }
        return conversations.first { $0.id == owner.conversationID }
    }

    var notificationCommandOwner: VyronNotificationResponseID? {
        guard interactions.pendingCommandApproval != nil,
            let generation = interactions.approvalGeneration
        else { return nil }
        if let response = foregroundRun.response(forGeneration: generation), ownsInteractiveWorkResponse(response) {
            return VyronNotificationResponseID(conversationID: response.conversationID, responseID: response.messageID)
        }
        guard isRunningScheduledTask, let run = scheduledTasks.reviewableRun,
            run.id == generation, let conversationID = run.output.conversationID,
            let responseID = conversations.first(where: { $0.id == conversationID })?.messages.last?.id
        else { return nil }
        return VyronNotificationResponseID(conversationID: conversationID, responseID: responseID)
    }

    func reviewDevelopmentCommand(_ approval: CommandApproval, generationID: UUID) async -> Bool {
        guard canReviewCommand(generationID), !Task.isCancelled else { return false }
        return await interactions.reviewCommand(
            approval,
            generationID: generationID,
            canPresent: { canReviewCommand(generationID) },
            willPresent: {
                if isRunningScheduledTask, scheduledTasks.reviewableRun?.id == generationID {
                    appNavigation.showScheduledTasks = false
                }
            }
        )
    }

    func ownsInteractiveWorkResponse(_ response: VyronResponseIdentity) -> Bool {
        guard !isShuttingDown, !Task.isCancelled else { return false }
        if foregroundRun.activeResponse == response { return selectedConversationID == response.conversationID }
        return foregroundRun.isDevelopmentResponse(response)
    }

    private func canReviewCommand(_ generationID: UUID) -> Bool {
        guard !isShuttingDown else { return false }
        if let response = foregroundRun.response(forGeneration: generationID) {
            return ownsInteractiveWorkResponse(response)
        }
        return isRunningScheduledTask && scheduledTasks.reviewableRun?.id == generationID
    }

    private func canPresentCommandApproval(_ generationID: UUID) -> Bool {
        guard canReviewCommand(generationID) else { return false }
        if let response = foregroundRun.response(forGeneration: generationID) {
            return response.conversationID == selectedConversationID
        }
        return true
    }

    func respondToCommandApproval(_ approved: Bool, approvalID: UUID? = nil) {
        if let approvalID {
            guard interactions.pendingCommandApproval?.id == approvalID,
                let generation = interactions.approvalGeneration else { return }
            guard canReviewCommand(generation) else {
                interactions.respondToCommandApproval(false, approvalID: approvalID)
                return
            }
            guard selectedCommandApproval?.id == approvalID else { return }
        }
        if approved, interactions.approvalGeneration.map(canPresentCommandApproval) != true { return }
        interactions.respondToCommandApproval(approved, approvalID: approvalID)
    }

    func dismissCommandApproval(generationID: UUID) {
        guard interactions.approvalGeneration == generationID else { return }
        interactions.respondToCommandApproval(false)
    }
}
