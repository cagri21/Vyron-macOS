import Foundation

public struct VyronSkillDiscoveryIssue: Sendable, Equatable {
    public let fileURL: URL
    public let reason: VyronSkillIssueReason

    public init(fileURL: URL, reason: VyronSkillIssueReason) {
        self.fileURL = fileURL
        self.reason = reason
    }
}
