import VyronLocalization

/// Chooses command review and execution capabilities for an interactive Work response.
/// Plan remains read-only in every access setting.
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
