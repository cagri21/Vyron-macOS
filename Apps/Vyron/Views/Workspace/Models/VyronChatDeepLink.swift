import Foundation

/// A local navigation address; links never carry prompts, commands, or file paths.
struct VyronChatDeepLink: Equatable {
    static let scheme = "vyron"
    private static let host = "chat"

    let conversationID: UUID

    init(conversationID: UUID) {
        self.conversationID = conversationID
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == Self.scheme,
            components.host?.lowercased() == Self.host,
            components.user == nil, components.password == nil, components.port == nil,
            components.query == nil, components.fragment == nil,
            components.path.hasPrefix("/"),
            let id = UUID(uuidString: String(components.path.dropFirst())) else { return nil }
        conversationID = id
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.path = "/" + conversationID.uuidString.lowercased()
        return components.url
    }
}
