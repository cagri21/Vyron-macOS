import Foundation

struct VyronDevelopmentTaskLifecycle: Codable, Sendable, Equatable {
    var status: VyronDevelopmentTaskStatus
    var updatedAt: Date
    var detail: String?

    init(status: VyronDevelopmentTaskStatus = .running, updatedAt: Date = Date(), detail: String? = nil) {
        self.status = status
        self.updatedAt = updatedAt
        self.detail = detail
    }
}
