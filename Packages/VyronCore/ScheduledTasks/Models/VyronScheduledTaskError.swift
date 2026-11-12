import Foundation

public enum VyronScheduledTaskError: Error, Equatable, Sendable {
    case invalidSchedule
    case invalidTask
    case invalidStore
    case unsupportedVersion
    case storeUnavailable
}
