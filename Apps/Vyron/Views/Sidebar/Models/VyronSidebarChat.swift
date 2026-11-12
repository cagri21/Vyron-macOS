import VyronCore

struct VyronSidebarChat {
    let conversation: Conversation
    let isPinned: Bool
    let showsProject: Bool

    var hasFailedResponse: Bool {
        conversation.messages.last(where: { $0.conversationRole == .assistant })?.activity?.state == .failed
    }
}
