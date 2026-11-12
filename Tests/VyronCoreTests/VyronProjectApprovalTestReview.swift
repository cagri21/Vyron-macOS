import Foundation
import VyronCore

actor VyronProjectApprovalTestReview {
    private var continuation: CheckedContinuation<Bool, Never>?
    private(set) var requests: [CommandApproval] = []

    func waitForDecision(_ request: CommandApproval) async -> Bool {
        requests.append(request)
        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve(_ approved: Bool) {
        continuation?.resume(returning: approved)
        continuation = nil
    }
}
