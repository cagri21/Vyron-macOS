import Foundation

public struct VyronFolderCreationRequest: Sendable {
    public let path: String
    public let projectURL: URL

    public init(path: String, projectURL: URL) {
        self.path = path
        self.projectURL = projectURL
    }
}
