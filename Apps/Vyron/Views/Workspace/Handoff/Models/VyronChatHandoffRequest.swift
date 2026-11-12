struct VyronChatHandoffRequest {
    let source: VyronChatHandoffPresentation
    let destination: VyronChatHandoffSelection
    let prompt: String
    let startsImmediately: Bool
}
