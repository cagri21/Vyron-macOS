import Foundation

struct VyronDevelopmentIntegrationProgress: Codable, Sendable, Equatable {
    let identity: VyronDevelopmentIntegrationIdentity
    let status: VyronDevelopmentIntegrationStatus
    let summary: String
    let recordedAt: Date

    var toolName: String { identity.toolName }
    var argumentsHash: String { identity.argumentsHash }
    var succeeded: Bool { status == .succeeded }

    init(
        identity: VyronDevelopmentIntegrationIdentity,
        status: VyronDevelopmentIntegrationStatus,
        summary: String,
        recordedAt: Date = Date()
    ) {
        self.identity = identity
        self.status = status
        self.summary = VyronDevelopmentTaskText.prefix(
            summary.replacingOccurrences(of: "\0", with: ""),
            maximumBytes: VyronDevelopmentTaskLimits.maximumSummaryBytes
        )
        self.recordedAt = recordedAt
    }
}
