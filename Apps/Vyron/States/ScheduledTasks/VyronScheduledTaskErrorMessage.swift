import Foundation
import VyronCore
import VyronModelDomain

enum VyronScheduledTaskErrorMessage {
    static func message(for error: Error) -> String {
        guard let error = error as? VyronScheduledTaskError else { return error.localizedDescription }
        switch error {
        case .invalidSchedule: return VyronScheduledTaskText.invalidSchedule
        case .invalidTask:
            return VyronScheduledTaskText.invalidTask(
                VyronTaskPromptLimits.localizedMaximumCharacters,
                VyronTaskPromptLimits.localizedMaximumKilobytes
            )
        case .invalidStore: return VyronScheduledTaskText.invalidStore
        case .unsupportedVersion: return VyronScheduledTaskText.unsupportedVersion
        case .storeUnavailable: return VyronScheduledTaskText.storeUnavailable
        }
    }
}
