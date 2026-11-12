import Foundation
import VyronCore

struct VyronTaskOverviewSnapshot: Sendable {
    let conversationID: UUID?
    let project: VyronTaskOverviewProject
    let response: ChatMessage?
    let sources: [VyronImageAttachment]

    init(conversation: Conversation?, project: VyronTaskOverviewProject) {
        conversationID = conversation?.id
        self.project = project
        let messages = conversation?.messages ?? []
        let ownership = VyronConversationResponseOwnership(messages: messages)
        let latest = messages.last { $0.conversationRole == .assistant && !ownership.isChild($0) }
        response = latest?.activity == nil ? nil : latest
        var seen: Set<UUID> = []
        sources = messages.filter { $0.conversationRole == .user }
            .flatMap { $0.images ?? [] }.filter { seen.insert($0.id).inserted }
    }
}
