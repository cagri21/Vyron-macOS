import Combine

@MainActor
final class VyronChatHandoffFlow: ObservableObject {
    @Published var chatHandoffPresentation: VyronChatHandoffPresentation?
    var preparedChatHandoffDraft: VyronPreparedChatHandoffDraft?
    var pendingNativeChatHandoff: VyronPendingChatHandoff?
}
