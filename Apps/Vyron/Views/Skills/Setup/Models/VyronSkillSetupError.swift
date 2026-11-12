import Foundation

enum VyronSkillSetupError: LocalizedError {
    case failed
    case nameConflict

    var errorDescription: String? {
        switch self {
        case .failed: VyronSkillText.automaticSetupFailed
        case .nameConflict: VyronSkillText.automaticSetupConflict
        }
    }
}
