import Foundation

public struct VyronWebSource: Sendable, Equatable {
    public let title: String
    public let url: URL
    public let excerpt: String

    public init(title: String, url: URL, excerpt: String) {
        self.title = title
        self.url = url
        self.excerpt = excerpt
    }
}
