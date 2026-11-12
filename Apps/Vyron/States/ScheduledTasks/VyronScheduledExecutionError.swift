import Foundation

enum VyronScheduledExecutionError: Error, LocalizedError {
    case connectionMissing
    case projectRequired
    case noAutomaticModel
    case historyUnavailable

    var errorDescription: String? {
        switch self {
        case .connectionMissing: return VyronScheduledTaskText.connectionMissing
        case .projectRequired: return VyronScheduledTaskText.projectRequired
        case .noAutomaticModel: return VyronScheduledTaskText.noAutomaticModel
        case .historyUnavailable: return VyronScheduledTaskText.historyUnavailable
        }
    }
}
