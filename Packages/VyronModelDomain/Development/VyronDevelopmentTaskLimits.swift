import Foundation

package enum VyronDevelopmentTaskLimits {
    package static let maximumGoalBytes = 128_000
    package static let maximumPlanSteps = 12
    package static let maximumStepBytes = 512
    package static let maximumFiles = 256
    package static let maximumChecks = 64
    package static let maximumIntegrations = 64
    package static let maximumFileOperations = 64
    package static let fileOperationOutcomeReserveBytes = 2 * maximumSummaryBytes + 256
    package static let maximumDecisions = 16
    package static let maximumGuidanceEntries = 64
    package static let maximumGuidanceBytes = 128_000
    package static let maximumContinuationResponses = 256
    package static let maximumSummaryBytes = 1_024
    package static let maximumStoredBytes = 2_000_000
    package static let defaultContextBytes = 4_096

    package static func requiresTextAttachment(_ goal: String) -> Bool {
        goal.utf8.count > VyronTaskPromptLimits.maximumUTF8Bytes || goal.count > VyronTaskPromptLimits.maximumCharacters
    }
}
