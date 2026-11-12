import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOllamaRecoveryDiagnosticTests: XCTestCase {
    override func tearDown() {
        VyronOllamaDevelopmentRepairURLProtocol.state.reset()
        super.tearDown()
    }

    func testExhaustedInternalInferenceCarriesSafeDiagnosticsWhilePublicErrorContractStaysUnchanged() async throws {
        let data = Data(#"{"done":true,"done_reason":"stop","message":{"role":"assistant","content":"","thinking":"PRIVATE_THINKING"},"eval_count":1,"prompt_eval_count":4237}"#.utf8)
        VyronOllamaDevelopmentRepairURLProtocol.state.configure { _, _ in data }
        let client = try VyronOllamaDevelopmentRepairFixture.client()
        let request = VyronDevelopmentInferenceRequest(
            model: VyronOllamaDevelopmentRepairFixture.model,
            messages: [DevelopmentMessage(role: "user", content: "PRIVATE_PROMPT")],
            configuration: VyronDevelopmentInferenceConfiguration(effort: .balanced, mode: .agent, externalTools: [])
        )
        do {
            _ = try await client.developmentInference(request)
            XCTFail("The agent-facing boundary must identify exhausted content recovery.")
        } catch let failure as VyronDevelopmentReplyFailure {
            XCTAssertEqual(failure.diagnostic.attempt, 2)
            XCTAssertEqual(failure.diagnostic.response.finishReason, "stop")
            XCTAssertEqual(failure.diagnostic.response.generatedTokens, 1)
            XCTAssertEqual(failure.diagnostic.response.promptTokens, 4237)
            XCTAssertGreaterThan(failure.diagnostic.request.messageBytes, 0)
            XCTAssertFalse(failure.diagnostic.summary.contains("PRIVATE"))
            XCTAssertEqual(failure.originalError, .invalidResponse(
                "The local model finished without an answer or a native tool call."
            ))
        }

        do {
            _ = try await client.developmentStep(model: request.model, messages: request.messages)
            XCTFail("The public provider boundary must preserve its previous failure.")
        } catch LocalAIError.invalidResponse(let detail) {
            XCTAssertEqual(detail, "The local model finished without an answer or a native tool call.")
        }
    }

    func testOptionalMalformedCountsAndUnknownReasonsCannotLeakProviderText() throws {
        let counts: [Any] = [true, -1, 0.5, "PRIVATE_COUNTER", ["PRIVATE": "DATA"]]
        for count in counts {
            let data = try JSONSerialization.data(withJSONObject: [
                "eval_count": count, "prompt_eval_count": count, "message": ["thinking": "PRIVATE_THINKING"]
            ])
            let metrics = VyronOllamaResponseMetrics.decode(data: data, reason: "PRIVATE_DONE_REASON")
            XCTAssertEqual(metrics.finishReason, "other")
            XCTAssertNil(metrics.generatedTokens)
            XCTAssertNil(metrics.promptTokens)
        }
    }

    func testOutputLimitedRepliesReachAgentRecoveryWithoutAcceptingThePartialAnswer() async throws {
        let partial = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", content: "PARTIAL_UNFINISHED"), reason: "length"
        )
        let final = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", content: "The inspection is complete.")
        )
        VyronOllamaDevelopmentRepairURLProtocol.state.configure { attempt, _ in attempt <= 2 ? partial : final }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VyronLength-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let result = try await DevelopmentAgent(
            client: VyronOllamaDevelopmentRepairFixture.client(), workspace: DevelopmentWorkspace(rootURL: directory)
        ).run(
            goal: "Inspect the local project and give a final answer.",
            model: VyronOllamaDevelopmentRepairFixture.model, automaticModelSelection: false,
            onEvent: { _ in }, approveCommand: { _ in false }
        )
        XCTAssertTrue(result.isComplete)
        XCTAssertTrue(result.finalMessage.hasPrefix("The inspection is complete."))
        XCTAssertFalse(result.finalMessage.contains("PARTIAL_UNFINISHED"))
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertTrue(result.changedFiles.isEmpty)
        XCTAssertEqual(VyronOllamaDevelopmentRepairURLProtocol.state.requests.count, 3)
        XCTAssertTrue(VyronOllamaDevelopmentRepairURLProtocol.state.requests.allSatisfy {
            !String(decoding: $0, as: UTF8.self).contains("PARTIAL_UNFINISHED")
        })
    }
}
