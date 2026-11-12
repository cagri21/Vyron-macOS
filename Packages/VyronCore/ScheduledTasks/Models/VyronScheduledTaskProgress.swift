import Foundation

public struct VyronScheduledTaskProgress: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var nextRunAt: Date?
    public var lastRun: VyronScheduledTaskRun?

    public init(isEnabled: Bool, nextRunAt: Date?, lastRun: VyronScheduledTaskRun?) {
        self.isEnabled = isEnabled
        self.nextRunAt = nextRunAt
        self.lastRun = lastRun
    }
}
