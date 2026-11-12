import Foundation

enum VyronSidebarChatPreview {
    static let limit = 5

    static func visibleChats(
        _ conversations: [Conversation],
        selectedID: UUID?,
        showsAll: Bool
    ) -> [Conversation] {
        guard !showsAll, conversations.count > limit else { return conversations }

        let preview = Array(conversations.prefix(limit))
        guard let selectedID,
            !preview.contains(where: { $0.id == selectedID }),
            let selected = conversations.dropFirst(limit).first(where: { $0.id == selectedID })
        else { return preview }

        return Array(preview.prefix(limit - 1)) + [selected]
    }
}
