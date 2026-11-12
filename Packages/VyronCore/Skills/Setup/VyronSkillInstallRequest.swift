import Foundation

public struct VyronSkillInstallRequest: Sendable {
    public let packageDirectory: URL
    public let installationDirectory: URL
    public let identifier: String

    public init(packageDirectory: URL, installationDirectory: URL, identifier: String) {
        self.packageDirectory = packageDirectory
        self.installationDirectory = installationDirectory
        self.identifier = identifier
    }
}
