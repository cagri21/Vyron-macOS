import Foundation

public struct VyronFolderCreationResult: Sendable {
    public let url: URL
    public let created: Bool

    public init(url: URL, created: Bool) {
        self.url = url
        self.created = created
    }
}
