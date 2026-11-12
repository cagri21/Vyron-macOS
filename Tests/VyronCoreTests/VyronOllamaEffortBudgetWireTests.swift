import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOllamaEffortBudgetWireTests: XCTestCase {
    override func tearDown() {
        VyronOllamaDevelopmentRepairURLProtocol.state.reset()
        super.tearDown()
    }

    func testChatAndDevelopmentSendSixDistinctOutputBudgetsWithoutChangingManualModelOrContext() async throws {
        let efforts: [AgentEffort] = [.quick, .balanced, .deep, .extraHigh, .maximum, .ultra]
        let expected = [2_048, 4_096, 6_144, 8_192, 10_240, 12_288]
        for (effort, outputTokens) in zip(efforts, expected) {
            let settings = ModelSettings(contextTokens: 32_768, temperature: 0.3, topP: 0.75, thinking: false)
            let client = try VyronOllamaDevelopmentRepairFixture.client(settings: settings)
            try configureReply()
            let answer = try await VyronChatInference.response(
                using: client, request: request(effort), onToken: { _ in }
            )
            XCTAssertEqual(answer, "A complete public answer.")
            try assertLastRequest(outputTokens: outputTokens, contextTokens: 32_768)
            try configureReply()
            let step = try await client.developmentStep(
                model: VyronOllamaDevelopmentRepairFixture.model,
                messages: [DevelopmentMessage(role: "user", content: "Inspect this project.")], effort: effort
            )
            XCTAssertEqual(step.message.content, "A complete public answer.")
            try assertLastRequest(outputTokens: outputTokens, contextTokens: 32_768)
        }
    }

    func testSavedOutputCapWinsOverEveryManualProfileInChatAndDevelopment() async throws {
        let settings = ModelSettings(contextTokens: 32_768, maxOutputTokens: 1_024, thinking: false)
        for effort in [AgentEffort.quick, .balanced, .deep, .extraHigh, .maximum, .ultra] {
            let client = try VyronOllamaDevelopmentRepairFixture.client(settings: settings)
            try configureReply()
            _ = try await VyronChatInference.response(using: client, request: request(effort), onToken: { _ in })
            try assertLastRequest(outputTokens: 1_024, contextTokens: 32_768)
            try configureReply()
            _ = try await client.developmentStep(
                model: VyronOllamaDevelopmentRepairFixture.model,
                messages: [DevelopmentMessage(role: "user", content: "Inspect this project.")], effort: effort
            )
            try assertLastRequest(outputTokens: 1_024, contextTokens: 32_768)
        }
    }

    func testUltraChatFitsWithinExplicitSmallContextWithoutDroppingUserGuidance() async throws {
        let settings = ModelSettings(contextTokens: 8_192, thinking: false)
        let client = try VyronOllamaDevelopmentRepairFixture.client(settings: settings)
        let guidance = "Retain this exact user instruction. " + String(repeating: "u", count: 1_000)
        try configureReply()
        let input = VyronChatInferenceRequest(
            model: VyronOllamaDevelopmentRepairFixture.model,
            messages: [ChatMessage(role: "user", content: guidance)],
            configuration: VyronChatInferenceConfiguration(systemPrompt: nil, effort: .ultra)
        )
        _ = try await VyronChatInference.response(using: client, request: input, onToken: { _ in })
        let body = try VyronOllamaDevelopmentRepairFixture.fields(
            XCTUnwrap(VyronOllamaDevelopmentRepairURLProtocol.state.requests.last)
        )
        let options = try options(in: body)
        XCTAssertEqual(options["num_ctx"], .number(8_192))
        guard case .number(let output) = options["num_predict"] else {
            XCTFail("The output allowance must be encoded as a number.")
            throw URLError(.cannotDecodeContentData)
        }
        let messages = try VyronOllamaDevelopmentRepairFixture.messages(
            in: XCTUnwrap(VyronOllamaDevelopmentRepairURLProtocol.state.requests.last)
        )
        XCTAssertEqual(messages.map(\.content), [guidance])
        let inputBytes = try JSONEncoder().encode(messages).count + 2_048
        XCTAssertLessThanOrEqual(Double(inputBytes) + output, 8_192)
        XCTAssertLessThan(output, Double(AgentEffort.ultra.developmentBudget.outputTokens))
    }

    func testLegacyPublicChatAndAutomaticKeepExistingOutputDefault() async throws {
        let client = try VyronOllamaDevelopmentRepairFixture.client(settings: ModelSettings(thinking: false))
        try configureReply()
        _ = try await client.chat(
            model: VyronOllamaDevelopmentRepairFixture.model,
            messages: [ChatMessage(role: "user", content: "Hello")], onToken: { _ in }
        )
        try assertLastRequest(outputTokens: 4_096, contextTokens: 32_768)
        try configureReply()
        _ = try await VyronChatInference.response(using: client, request: request(.automatic), onToken: { _ in })
        try assertLastRequest(outputTokens: 4_096, contextTokens: 32_768)
    }

    private func request(_ effort: AgentEffort) -> VyronChatInferenceRequest {
        VyronChatInferenceRequest(
            model: VyronOllamaDevelopmentRepairFixture.model,
            messages: [ChatMessage(role: "user", content: "Inspect this project.")],
            configuration: VyronChatInferenceConfiguration(systemPrompt: nil, effort: effort)
        )
    }

    private func configureReply() throws {
        var reply = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", content: "A complete public answer.")
        )
        reply.append(10)
        let data = reply
        VyronOllamaDevelopmentRepairURLProtocol.state.configure { _, _ in data }
    }

    private func assertLastRequest(outputTokens: Int, contextTokens: Int) throws {
        let requests = VyronOllamaDevelopmentRepairURLProtocol.state.requests
        XCTAssertEqual(requests.count, 1)
        let body = try VyronOllamaDevelopmentRepairFixture.fields(XCTUnwrap(requests.last))
        XCTAssertEqual(body["model"], .string(VyronOllamaDevelopmentRepairFixture.model))
        XCTAssertEqual(body["think"], .bool(false))
        let options = try options(in: body)
        XCTAssertEqual(options["num_predict"], .number(Double(outputTokens)))
        XCTAssertEqual(options["num_ctx"], .number(Double(contextTokens)))
    }

    private func options(in body: [String: DevelopmentJSONValue]) throws -> [String: DevelopmentJSONValue] {
        guard case .object(let options) = body["options"] else {
            XCTFail("The request must carry explicit provider options.")
            throw URLError(.cannotDecodeContentData)
        }
        return options
    }
}
