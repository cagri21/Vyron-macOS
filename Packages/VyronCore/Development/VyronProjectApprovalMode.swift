import VyronLocalization

/// Chooses when a permitted project command needs review.
/// Command validation and the local execution restrictions apply in every mode.
public enum VyronProjectApprovalMode: String, Codable, CaseIterable, Sendable {
    case askForApproval
    case approveForMe
    case fullAccess

    public func commandReviewReason(for classifiedReason: String?) -> String? {
        switch self {
        case .askForApproval:
            classifiedReason ?? VyronProjectApprovalText.defaultReviewReason
        case .approveForMe:
            classifiedReason
        case .fullAccess:
            nil
        }
    }
}
