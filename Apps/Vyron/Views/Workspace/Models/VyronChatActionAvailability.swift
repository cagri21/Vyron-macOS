import Foundation

/// A menu snapshot belongs to one saved chat; actions revalidate its identity before making changes.
struct VyronChatActionAvailability {
    let conversationID: UUID
    let title: String
    let isPinned: Bool
    let navigation: VyronChatActionNavigationAvailability

    var canRename: Bool { true }
    var canPin: Bool { true }
    var canExport: Bool { true }
    var canContinue: Bool { navigation.canContinue }
    var canArchive: Bool { navigation.canArchive }
}
