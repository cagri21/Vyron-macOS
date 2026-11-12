import Foundation

enum VyronCompactionError: LocalizedError {
    case noHistory
    case alreadyCompact
    case inputTooLarge
    case invalidSummary
    case attachments
    case saveFailed
    case contextFull

    var errorDescription: String? {
        switch self {
        case .noHistory: VyronCompactionText.noHistory
        case .alreadyCompact: VyronCompactionText.alreadyCompact
        case .inputTooLarge: VyronCompactionText.inputTooLarge
        case .invalidSummary: VyronCompactionText.invalidSummary
        case .attachments: VyronCompactionText.attachments
        case .saveFailed: VyronCompactionText.saveFailed
        case .contextFull: VyronCompactionText.contextFull
        }
    }
}
