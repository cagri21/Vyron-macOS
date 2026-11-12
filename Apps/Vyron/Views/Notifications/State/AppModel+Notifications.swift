import Foundation
import VyronCore

extension AppModel {
    var notificationGroups: [VyronNotificationGroup] {
        let visible = conversations.filter { !sidebarState.sidebarOrganization.isConversationArchived($0.id) }
        return notifications.groups(conversations: visible, runtime: notificationRuntime)
    }

    var notificationItems: [VyronNotificationItem] { notificationGroups.flatMap(\.items) }
    var unreadNotificationCount: Int { notificationItems.filter(\.isUnread).count }

    var notificationRuntime: VyronNotificationRuntime {
        var live: Set<VyronNotificationResponseID> = []
        for conversation in conversations {
            for message in conversation.messages where message.conversationRole == .assistant
                && message.activity?.state == .working {
                if isResponseActivityLive(conversationID: conversation.id, messageID: message.id) {
                    live.insert(VyronNotificationResponseID(conversationID: conversation.id, responseID: message.id))
                }
            }
        }
        var attention: [VyronNotificationAttention] = []
        if let request = interactions.pendingUserInput, let observedAt = interactions.userInputObservedAt,
            let conversationID = interactions.userInputConversationID,
            let generationID = interactions.userInputGeneration,
            let owner = foregroundRun.response(forGeneration: generationID),
            owner.conversationID == conversationID, ownsInteractiveWorkResponse(owner) {
            let response = VyronNotificationResponseID(
                conversationID: conversationID, responseID: owner.messageID
            )
            if let item = notificationAttention(
                response: response, requestID: request.id,
                preview: request.questions.first?.question ?? "", date: observedAt
            ) { attention.append(item) }
        }
        if let approval = interactions.pendingCommandApproval, let observedAt = interactions.commandObservedAt,
            let owner = notificationCommandOwner,
            let item = notificationAttention(
                response: owner, requestID: approval.id,
                preview: VyronNotificationText.approvalRequested, date: observedAt
            ) { attention.append(item) }
        if let review = mcpConnections.pendingReview,
            let observation = notifications.reviewObservation, observation.requestID == review.id {
            if case .response(let owner) = observation.target,
                let item = notificationAttention(
                    response: owner, requestID: review.id,
                    preview: VyronNotificationText.pluginApprovalRequested, date: observation.observedAt
                ) {
                attention.append(item)
            } else if observation.target == .plugins {
                attention.append(VyronNotificationAttention(
                    target: .plugins, attentionID: review.id,
                    content: VyronNotificationContent(
                        title: VyronPluginText.title, preview: VyronNotificationText.pluginApprovalRequested,
                        projectPath: nil
                    ), date: observation.observedAt
                ))
            }
        }
        return VyronNotificationRuntime(
            liveResponses: live, attention: attention, scheduledItems: scheduledNotifications
        )
    }

    var notificationDevelopmentOwners: Set<VyronNotificationResponseID> {
        var owners: Set<VyronNotificationResponseID> = []
        if let work = foregroundRun.developmentResponse
            ?? (foregroundRun.isDeveloping ? foregroundRun.activeResponse : nil) {
            owners.insert(VyronNotificationResponseID(
                conversationID: work.conversationID, responseID: work.messageID
            ))
        }
        if isRunningScheduledTask, let taskID = scheduledTasks.activeTaskID,
            let task = scheduledTasks.tasks.first(where: { $0.id == taskID }), task.definition.context.mode != .chat,
            let run = task.progress.lastRun, run.state == .running, let conversationID = run.output.conversationID,
            let responseID = conversations.first(where: { $0.id == conversationID })?.messages.last?.id {
            owners.insert(VyronNotificationResponseID(conversationID: conversationID, responseID: responseID))
        }
        return owners.filter { isResponseActivityLive(conversationID: $0.conversationID, messageID: $0.responseID) }
    }

    var canPresentMCPReview: Bool {
        guard !isShuttingDown, let review = mcpConnections.pendingReview,
            let observation = notifications.reviewObservation, observation.requestID == review.id else { return false }
        switch observation.target {
        case .response(let owner):
            guard isResponseActivityLive(conversationID: owner.conversationID, messageID: owner.responseID)
            else { return false }
            if isRunningScheduledTask, scheduledTasks.reviewableRun?.output.conversationID == owner.conversationID {
                return true
            }
            return selectedConversationID == owner.conversationID
        case .plugins:
            return true
        case .scheduledRun:
            return false
        }
    }

    private func notificationAttention(
        response: VyronNotificationResponseID,
        requestID: UUID,
        preview: String,
        date: Date
    ) -> VyronNotificationAttention? {
        guard isResponseActivityLive(conversationID: response.conversationID, messageID: response.responseID),
            let conversation = conversations.first(where: { $0.id == response.conversationID }),
            !sidebarState.sidebarOrganization.isConversationArchived(conversation.id)
        else { return nil }
        return VyronNotificationAttention(
            target: .response(response), attentionID: requestID,
            content: VyronNotificationContent(
                title: conversation.title, preview: preview, projectPath: conversation.sidebarProjectPath
            ), date: date
        )
    }

    private var scheduledNotifications: [VyronNotificationItem] {
        scheduledTasks.tasks.compactMap { task in
            guard let run = task.progress.lastRun, run.output.conversationID == nil,
                scheduledTasks.committedTerminalRunIDs.contains(run.id),
                let date = run.output.finishedAt, run.state == .completed || run.state == .failed else { return nil }
            return VyronNotificationItem(
                id: VyronNotificationID(
                    target: .scheduledRun(VyronNotificationScheduledRunID(taskID: task.id, runID: run.id)),
                    kind: run.state == .completed ? .completed : .failed
                ),
                content: VyronNotificationContent(
                    title: task.definition.title, preview: run.output.detail ?? "",
                    projectPath: task.definition.context.projectPath
                ), date: date, isRead: false
            )
        }
    }
}
