import XCTest
@testable import VyronCore

@MainActor
final class VyronChatEffortDispatchTests: XCTestCase {
    func testProviderWithoutOptionalEffortCapabilityRetainsItsExistingPublicChatFailure() async throws {
        let provider = VyronContinuationEffortTestProvider()
        for effort in [AgentEffort.quick, .ultra] {
            do {
                _ = try await VyronChatInference.response(
                    using: provider, request: request(effort), onToken: { _ in }
                )
                XCTFail("The legacy provider's original error must propagate.")
            } catch {
                XCTAssertEqual(error as? ModelProviderError, .unsupportedTools)
            }
        }
    }

    func testCancelledDispatchStopsBeforeCallingLegacyProvider() async throws {
        let provider = VyronContinuationEffortTestProvider()
        let request = request(.ultra)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await VyronChatInference.response(using: provider, request: request, onToken: { _ in })
        }
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled dispatch must stop before the provider can return its unrelated error.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func request(_ effort: AgentEffort) -> VyronChatInferenceRequest {
        VyronChatInferenceRequest(
            model: "exact-manual-model:q4", messages: [ChatMessage(role: "user", content: "Explain this task.")],
            configuration: VyronChatInferenceConfiguration(systemPrompt: nil, effort: effort)
        )
    }
}
