import Foundation
import VyronCore

actor VyronFeatureTestProvider: ModelProvider {
    private(set) var chatRequests = 0
    private(set) var verificationRequests = 0
    private(set) var developmentRequests = 0
    private var verificationFailure: ModelProviderError?
    private var holdsVerification = false
    private var verificationContinuations: [Int: CheckedContinuation<Void, Never>] = [:]

    func holdVerification() { holdsVerification = true }

    func releaseVerification() {
        holdsVerification = false
        let continuations = verificationContinuations.values
        verificationContinuations = [:]
        for continuation in continuations { continuation.resume() }
    }

    func releaseVerification(_ request: Int) {
        verificationContinuations.removeValue(forKey: request)?.resume()
    }

    func failVerification(with error: ModelProviderError?) { verificationFailure = error }

    func models() async throws -> [LocalModel] { [] }

    // Existing ModelProvider transport requirements determine these method signatures.
    func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        if systemPrompt?.contains("Generate suggested follow-up questions") == true {
            return #"{"questions":[]}"#
        }
        chatRequests += 1
        onToken("Feature test answer")
        return "Feature test answer"
    }

    func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        verificationRequests += 1
        let request = verificationRequests
        if holdsVerification {
            // Deliberately finish after cancellation to exercise the selection's stale-result guard.
            await withCheckedContinuation { verificationContinuations[request] = $0 }
        }
        if let verificationFailure { throw verificationFailure }
        return LocalModel(name: model, size: 1, capabilities: ["tools"])
    }

    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        developmentRequests += 1
        return DevelopmentStep(message: DevelopmentMessage(role: "assistant", content: "Development answer"))
    }
}
