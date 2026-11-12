import Foundation

public struct VyronWebsiteCrawl: Sendable {
    public let pages: [VyronWebPage]
    public let unreadableURLs: [URL]
    public let reachedPageLimit: Bool
}
