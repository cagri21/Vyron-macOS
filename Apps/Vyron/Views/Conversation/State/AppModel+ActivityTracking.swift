import Foundation
import VyronCore

extension AppModel {
    var trackedMessage: ChatMessage? {
        guard let selection = appNavigation.trackingSelection, selection.conversationID == selectedConversationID else { return nil }
        return conversations.first { $0.id == selection.conversationID }?.messages.first {
            $0.id == selection.messageID
        }
    }

    var trackedSubagent: VyronSubagentActivity? {
        guard let id = appNavigation.trackingSelection?.subagentID else { return nil }
        return trackedMessage?.activity?.subagentActivities.first { $0.id == id }
    }

    var trackedActivity: ResponseActivity? {
        appNavigation.trackingSelection?.subagentID == nil ? trackedMessage?.activity : trackedSubagent?.activity
    }

    func openActivity(
        conversationID: UUID,
        messageID: UUID,
        subagentID: UUID? = nil,
        entryID: UUID? = nil
    ) {
        guard conversationID == selectedConversationID,
            let activity = conversations.first(where: { $0.id == conversationID })?.messages.first(where: {
                $0.id == messageID
            })?.activity,
            subagentID == nil || activity.subagentActivities.contains(where: { $0.id == subagentID })
        else { return }
        let selectedActivity = subagentID.flatMap { id in
            activity.subagentActivities.first { $0.id == id }?.activity
        } ?? activity
        guard entryID == nil || selectedActivity.entries.contains(where: { $0.id == entryID }) else { return }
        appNavigation.showWorkspace = false
        appNavigation.trackingSelection = VyronTrackingSelection(
            conversationID: conversationID, messageID: messageID, subagentID: subagentID, entryID: entryID
        )
    }

    func closeActivity() {
        appNavigation.trackingSelection = nil
    }

    func recordDevelopmentActivity(_ event: DevelopmentEvent, conversationID: UUID, messageID: UUID) {
        guard let content = localizedActivityContent(event),
            let ci = conversations.firstIndex(where: { $0.id == conversationID }),
            let mi = conversations[ci].messages.firstIndex(where: { $0.id == messageID })
        else { return }
        conversations[ci].messages[mi].activity?.record(content)
        saveHistory()
    }

    func recordSubagentEvent(_ event: VyronSubagentEvent, conversationID: UUID, messageID: UUID) {
        guard let ci = conversations.firstIndex(where: { $0.id == conversationID }),
            let mi = conversations[ci].messages.firstIndex(where: { $0.id == messageID }),
            conversations[ci].messages[mi].activity?.state == .working
        else { return }
        let content: VyronActivityContent?
        if case .activity(let update) = event.update {
            content = localizedActivityContent(update)
        } else {
            content = nil
        }
        conversations[ci].messages[mi].activity?.recordSubagent(event, content: content)
        saveHistory()
    }

    private func localizedActivityContent(_ event: DevelopmentEvent) -> VyronActivityContent? {
        guard let content = event.activityContent else { return nil }
        return VyronActivityContent(
            kind: content.kind,
            title: event.kind == .assistant ? VyronStatusText.aiExplanation : event.localizedMessage,
            detail: content.detail,
            category: content.category
        )
    }
}
