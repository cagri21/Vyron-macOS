import Foundation
import VyronModelDomain

actor VyronAutoLocalAppTestAssessment {
    private(set) var requests: [VyronAutoLocalRequest] = []
    private(set) var providerBuilds: [UUID] = []
    private var destination = "qwen3:4b"
    private var held = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var failure: ModelProviderError?

    func select(_ id: String) { destination = id }
    func hold() { held = true }
    func fail(_ error: ModelProviderError?) { failure = error }
    func recordBuild(_ id: UUID) { providerBuilds.append(id) }

    func release() {
        held = false
        waiter?.resume()
        waiter = nil
    }

    func assess(_ request: VyronAutoLocalRequest) async throws -> VyronAutoLocalDecision {
        requests.append(request)
        // Deliberately return after cancellation to exercise the app's stale response guard.
        if held { await withCheckedContinuation { waiter = $0 } }
        if let failure { throw failure }
        return VyronAutoLocalDecision(candidateID: destination, complexity: .complex, thinkingLevel: .high)
    }
}
