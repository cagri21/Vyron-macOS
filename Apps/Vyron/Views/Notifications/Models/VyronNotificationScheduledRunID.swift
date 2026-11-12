import Foundation

struct VyronNotificationScheduledRunID: Codable, Hashable, Sendable {
    let taskID: UUID
    let runID: UUID
}
