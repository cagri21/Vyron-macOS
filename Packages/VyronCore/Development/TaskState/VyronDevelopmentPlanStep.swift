import CryptoKit
import Foundation

struct VyronDevelopmentPlanStep: Identifiable, Codable, Sendable, Equatable {
    var id: String { SHA256.hash(data: Data(title.utf8)).map { String(format: "%02x", $0) }.joined() }
    let title: String
    let status: VyronDevelopmentPlanStepStatus

    init(title: String, status: VyronDevelopmentPlanStepStatus = .pending) {
        self.title = title
        self.status = status
    }
}
