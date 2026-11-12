import Foundation

public struct VyronWebPage: Sendable, Equatable {
    public let source: VyronWebSource
    public let text: String
    public let retrievedAt: Date
    public let links: [URL]

    public init(source: VyronWebSource, text: String, retrievedAt: Date = Date(), links: [URL] = []) {
        self.source = source
        self.text = text
        self.retrievedAt = retrievedAt
        self.links = links
    }
}
