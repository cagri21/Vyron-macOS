import VyronDevelopment

struct VyronConversationChangesActions {
    let reviewFile: (DevelopmentChange) -> Void
    let viewChanges: () -> Void
    let undo: (() -> Void)?
}
