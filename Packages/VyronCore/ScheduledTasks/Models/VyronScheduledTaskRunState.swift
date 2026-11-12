import Foundation

public enum VyronScheduledTaskRunState: String, Codable, Sendable {
    case running
    case completed
    case failed
    case stopped
    case interrupted
}
