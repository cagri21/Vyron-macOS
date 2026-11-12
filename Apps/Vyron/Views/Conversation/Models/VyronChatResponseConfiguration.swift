import VyronCore

struct VyronChatResponseConfiguration {
    let inference: VyronConversationInferenceSelection
    let mode: ComposerMode
    let requestKind: VyronAssistantRequestKind
    let inferenceLocation: String

    var usesWebEvidence: Bool { requestKind.usesWebEvidence }
}
