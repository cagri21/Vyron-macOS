import Foundation

public struct VyronOfficePublication: Sendable {
    public let path: String
    public let artifacts: [VyronOfficeArtifact]
    public let isDirectory: Bool

    public init(path: String, artifacts: [VyronOfficeArtifact], isDirectory: Bool) {
        self.path = path
        self.artifacts = artifacts
        self.isDirectory = isDirectory
    }
}
