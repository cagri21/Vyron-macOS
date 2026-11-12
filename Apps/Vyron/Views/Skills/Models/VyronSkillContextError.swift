import Foundation

enum VyronSkillContextError: LocalizedError {
    case tooLarge
    case unavailable
    case documentTooLarge

    var errorDescription: String? {
        switch self {
        case .tooLarge: VyronSkillText.contextTooLong
        case .unavailable: VyronSkillText.loadFailed
        case .documentTooLarge: VyronSkillText.documentTooLong
        }
    }
}
