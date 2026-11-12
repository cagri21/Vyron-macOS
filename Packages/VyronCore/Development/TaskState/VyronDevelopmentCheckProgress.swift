import Foundation

struct VyronDevelopmentCheckProgress: Codable, Sendable, Equatable {
    let command: String
    let result: VyronDevelopmentCheckResult
    let summary: String
    let recordedAt: Date

    init(command: String, result: VyronDevelopmentCheckResult, summary: String = "", recordedAt: Date = Date()) {
        self.command = command
        self.result = result
        self.summary = VyronDevelopmentTaskText.prefix(
            summary.replacingOccurrences(of: "\0", with: ""),
            maximumBytes: VyronDevelopmentTaskLimits.maximumSummaryBytes
        )
        self.recordedAt = recordedAt
    }
}
