import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOllamaAssessmentWireTests: XCTestCase {
    func testAssessmentUsesSupportedOffAndJSONWithoutChangingLaterConversationThinkingOrUltra() async throws {
        let client = try client(settings: ModelSettings(contextTokens: 32_768, thinking: true))
        let assessment = try await wire(client, request("boolean:latest", purpose: .modelAssessment))

        XCTAssertEqual(assessment["think"], .bool(false))
        XCTAssertEqual(assessment["format"], .string("json"))
        XCTAssertEqual(assessment["model"], .string("boolean:latest"))
        XCTAssertEqual(try options(assessment)["num_predict"], .number(2_048))

        let conversation = try await wire(client, request("boolean:latest", purpose: .conversation, effort: .ultra))

        XCTAssertEqual(conversation["think"], .bool(true))
        XCTAssertNil(conversation["format"])
        XCTAssertEqual(try options(conversation)["num_predict"], .number(12_288))
        XCTAssertEqual(try options(conversation)["num_ctx"], .number(32_768))
    }

    func testMandatoryThinkingAssessmentGetsStructuredHeadroomInsteadOfAnUnsupportedOffValue() async throws {
        let client = try client(settings: ModelSettings(contextTokens: 32_768))
        let assessment = try await wire(client, request("qwen3:4b", purpose: .modelAssessment))

        XCTAssertNil(assessment["think"], "A true-only thinking model cannot be sent think:false")
        XCTAssertEqual(assessment["format"], .string("json"))
        XCTAssertEqual(try options(assessment)["num_predict"], .number(4_096))
        XCTAssertEqual(try options(assessment)["num_ctx"], .number(32_768))

        let conversation = try await wire(client, request("qwen3:4b", purpose: .conversation))
        XCTAssertNil(conversation["format"])
        XCTAssertEqual(try options(conversation)["num_predict"], .number(2_048))
    }

    func testMandatoryThinkingHeadroomRespectsTheSavedOutputMaximum() async throws {
        let client = try client(settings: ModelSettings(contextTokens: 32_768, maxOutputTokens: 1_024))
        let assessment = try await wire(client, request("qwen3:4b", purpose: .modelAssessment))

        XCTAssertNil(assessment["think"])
        XCTAssertEqual(assessment["format"], .string("json"))
        XCTAssertEqual(try options(assessment)["num_predict"], .number(1_024))
    }

    func testMandatoryThinkingHeadroomFitsTheExplicitContextAndKeepsAllGuidance() async throws {
        let client = try client(settings: ModelSettings(contextTokens: 8_192))
        let goal = "Analyze this exact task. " + String(repeating: "a", count: 4_000)
        let assessment = try await wire(client, request("qwen3:4b", purpose: .modelAssessment, text: goal))
        let fields = try options(assessment)
        let messages = try XCTUnwrap(assessment["messages"])
        let inputBytes = try JSONEncoder().encode(messages).count + 2_048

        XCTAssertEqual(fields["num_ctx"], .number(8_192))
        XCTAssertEqual(fields["num_predict"], .number(Double(min(4_096, 8_192 - inputBytes))))
        XCTAssertLessThan(8_192 - inputBytes, 4_096)
        guard case .array(let sent) = messages, case .object(let user) = sent.last else {
            return XCTFail("The assessment must retain its user message")
        }
        XCTAssertEqual(user["content"], .string(goal))
    }

    func testPartialOffControlsAreUsedButNamedOnlyControlsAreNeverInvented() async throws {
        var settings = ModelSettings(contextTokens: 32_768)
        settings.thinkingLevel = .high
        let client = try client(settings: settings)
        for model in ["mixed:latest", "off-only:latest"] {
            let assessment = try await wire(client, request(model, purpose: .modelAssessment))
            XCTAssertEqual(assessment["think"], .bool(false), model)
            XCTAssertEqual(try options(assessment)["num_predict"], .number(2_048), model)
        }

        let named = try await wire(client, request("named:latest", purpose: .modelAssessment))
        XCTAssertEqual(named["think"], .string("high"))
        XCTAssertEqual(named["format"], .string("json"))
        XCTAssertEqual(try options(named)["num_predict"], .number(4_096))

        let unsupported = try await wire(client, request("plain:latest", purpose: .modelAssessment))
        XCTAssertNil(unsupported["think"])
        XCTAssertEqual(unsupported["format"], .string("json"))
        XCTAssertEqual(try options(unsupported)["num_predict"], .number(2_048))
    }

    func testAssessmentMetadataFailureAndCancellationPropagate() async throws {
        let client = try client(settings: ModelSettings(contextTokens: 32_768))
        do {
            _ = try await wire(client, request("metadata-failure:latest", purpose: .modelAssessment))
            XCTFail("Metadata failure cannot silently turn into an unverified assessment")
        } catch {
            XCTAssertEqual(error as? ModelProviderError, .http(500))
        }
        do {
            _ = try await wire(client, request("cancelled-metadata:latest", purpose: .modelAssessment))
            XCTFail("Cancellation must prevent the assessment")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func client(settings: ModelSettings) throws -> OllamaClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronOllamaAssessmentURLProtocol.self]
        let connection = ModelConnectionProfile(
            name: "Offline assessment wire test", kind: .ollama, endpoint: "http://localhost:11434",
            selectedModel: "qwen3:4b", settings: settings
        )
        return try OllamaClient(connection: connection, configuration: configuration)
    }

    private func request(
        _ model: String,
        purpose: VyronChatInferencePurpose,
        effort: AgentEffort = .quick,
        text: String = "Analyze this source code."
    ) -> VyronChatInferenceRequest {
        VyronChatInferenceRequest(
            model: model,
            messages: [ChatMessage(role: "user", content: text)],
            configuration: .init(systemPrompt: "Return a valid assessment.", effort: effort, purpose: purpose)
        )
    }

    private func wire(
        _ client: OllamaClient,
        _ request: VyronChatInferenceRequest
    ) async throws -> [String: DevelopmentJSONValue] {
        let response = try await VyronChatInference.response(using: client, request: request, onToken: { _ in })
        XCTAssertFalse(response.contains("PRIVATE_REASONING_MARKER"))
        return try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: Data(response.utf8))
    }

    private func options(_ fields: [String: DevelopmentJSONValue]) throws -> [String: DevelopmentJSONValue] {
        guard case .object(let options) = fields["options"] else { throw URLError(.cannotDecodeContentData) }
        return options
    }
}
