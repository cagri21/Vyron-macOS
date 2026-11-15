import Combine
import Foundation
import VyronCore

@MainActor
final class VyronNotificationsModel: ObservableObject {
    let readStore: VyronNotificationReadStore
    @Published private(set) var readState = VyronNotificationReadState()
    @Published private(set) var storageError: String?
    @Published private(set) var committedResponses: Set<VyronNotificationID> = []
    private(set) var storageWritable = true
    private(set) var reviewObservation: VyronNotificationReviewObservation?
    private var subscriptions: Set<AnyCancellable> = []

    init(readStore: VyronNotificationReadStore) {
        self.readStore = readStore
    }

    func reloadReadState() {
        do {
            readState = try readStore.load() ?? .empty
            storageWritable = true
            storageError = nil
        } catch {
            storageWritable = false
            storageError = VyronNotificationText.storageError
        }
    }

    func observe(
        _ connections: MCPConnectionsModel,
        scheduledTasks: VyronScheduledTasksModel,
        recordReview: @escaping @MainActor (MCPActionReview?) -> Void,
        isActive: @escaping @MainActor () -> Bool
    ) {
        subscriptions.removeAll()
        connections.$pendingReview.sink { [weak self, weak connections] review in
            let id = review?.id
            recordReview(review)
            Task { @MainActor [weak self, weak connections] in
                guard let self, isActive(), connections?.pendingReview?.id == id else { return }
                self.objectWillChange.send()
            }
        }.store(in: &subscriptions)
        scheduledTasks.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, isActive() else { return }
                self.objectWillChange.send()
            }
        }.store(in: &subscriptions)
    }

    func recordReview(_ id: UUID?, owners: () -> Set<VyronNotificationResponseID>) {
        guard let id else {
            reviewObservation = nil
            return
        }
        guard reviewObservation?.requestID != id else { return }
        let owners = owners()
        let target = owners.count == 1 ? owners.first.map(VyronNotificationTarget.response) : nil
        reviewObservation = VyronNotificationReviewObservation(
            requestID: id, observedAt: Date(), target: target ?? .plugins
        )
    }

    /// Terminal cards reflect successfully loaded or saved history, never a rolled-back final write.
    func commitResponses(in conversations: [Conversation]) {
        let responses = Set(conversations.flatMap { conversation in
            conversation.messages.compactMap { message -> VyronNotificationID? in
                guard message.conversationRole == .assistant, let activity = message.activity,
                    activity.finishedAt != nil
                else { return nil }
                return terminalID(conversationID: conversation.id, message: message)
            }
        })
        if responses != committedResponses { committedResponses = responses }
    }

    func groups(
        conversations: [Conversation],
        runtime: VyronNotificationRuntime
    ) -> [VyronNotificationGroup] {
        let visible = conversations.map { original in
            var conversation = original
            conversation.messages = original.messages.filter { message in
                guard let id = terminalID(conversationID: original.id, message: message) else { return true }
                return committedResponses.contains(id)
            }
            return conversation
        }
        return VyronNotificationFeed.build(
            conversations: visible, runtime: runtime,
            readState: readState, calendarContext: VyronNotificationCalendarContext()
        )
    }

    private func terminalID(conversationID: UUID, message: ChatMessage) -> VyronNotificationID? {
        guard let activity = message.activity, activity.state == .completed || activity.state == .failed else {
            return nil
        }
        return VyronNotificationID(
            target: .response(VyronNotificationResponseID(conversationID: conversationID, responseID: message.id)),
            kind: activity.state == .completed ? .completed : .failed
        )
    }

    @discardableResult
    func markRead(_ ids: [VyronNotificationID]) -> Bool {
        guard storageWritable else { return false }
        do {
            var updated = readState
            try updated.markAllRead(ids: ids)
            try readStore.save(updated)
            readState = updated
            storageError = nil
            return true
        } catch {
            storageWritable = false
            storageError = VyronNotificationText.storageError
            return false
        }
    }
}
