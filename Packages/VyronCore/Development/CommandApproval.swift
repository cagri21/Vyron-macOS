import Foundation

public struct CommandApproval: Identifiable, Sendable {
    public let id = UUID()
    public let command: String
    public let reason: String
    public let action: VyronDevelopmentApprovalAction
    package let reviewSource: VyronCommandReviewSource

    public init(command: String, reason: String, action: VyronDevelopmentApprovalAction = .command) {
        self.init(command: command, reason: reason, action: action, reviewSource: .classification)
    }

    init(
        command: String,
        reason: String,
        action: VyronDevelopmentApprovalAction = .command,
        reviewSource: VyronCommandReviewSource
    ) {
        self.command = command
        self.reason = reason
        self.action = action
        self.reviewSource = reviewSource
    }
}
