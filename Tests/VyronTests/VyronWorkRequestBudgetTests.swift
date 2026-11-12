import Foundation
import XCTest
import VyronDevelopment
@testable import Vyron
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronWorkRequestBudgetTests: XCTestCase {
    override func tearDown() async throws {
        await VyronWorkBudgetURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testFullWorkCatalogRetainsBalancedAndUltraOutputUsingExactInputCounts() async throws {
        let externalTools = VyronWebTools.definitions + VyronSkillResourceTools.definitions
            + VyronChatHandoffTools.definitions + VyronOfficeTools.definitions
            + VyronMacWorkRun.definitions + VyronChromeTools.definitions
        let suppliedTools = externalTools + [VyronParallelTaskTool.definition]
        let tools = try DevelopmentToolDefinition.available(mode: .agent, externalTools: suppliedTools)
        let expectedNames = Set(tools.map { $0.function.name })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronWorkBudgetURLProtocol.self]
        let profile = ModelConnectionProfile(
            name: "Offline full Work catalog", kind: .openAICompatible,
            endpoint: "https://api.openai.com/v1", selectedModel: "gpt-6.1-sol",
            settings: ModelSettings(contextTokens: 32_768)
        )
        for effort in [AgentEffort.balanced, .ultra] {
            await VyronWorkBudgetURLProtocol.state.reset()
            let messages = try await capturedMessages(effort: effort, externalTools: externalTools)
            let client = try VyronOpenAIResponsesClient(
                connection: profile, apiKey: "offline-work-budget-key", configuration: configuration
            )
            let step = try await client.developmentStep(
                model: "gpt-6.1-sol", messages: messages, effort: effort,
                mode: .agent, externalTools: suppliedTools
            )
            XCTAssertEqual(step.message.content, "Inspection complete.")
            let requests = await VyronWorkBudgetURLProtocol.state.requests
            let counts = requests.filter { $0.url?.path == "/v1/responses/input_tokens" }
            XCTAssertEqual(counts.count, 1, "The full catalog requires an exact count at both efforts")
            let countRequest = try XCTUnwrap(counts.first)
            let counted = try VyronWorkBudgetTransportState.body(countRequest)
            let generations = try requests.filter { $0.url?.path == "/v1/responses" }.compactMap { request in
                let body = try VyronWorkBudgetTransportState.body(request)
                return body["tool_choice"] == nil ? body : nil
            }
            XCTAssertEqual(generations.count, 1)
            let generation = try XCTUnwrap(generations.first)
            XCTAssertEqual(generation["max_output_tokens"] as? Int, effort.developmentBudget.outputTokens)
            XCTAssertEqual(counted["model"] as? String, generation["model"] as? String)
            for key in ["input", "tools"] {
                XCTAssertEqual(
                    try JSONSerialization.data(withJSONObject: counted[key] ?? [], options: .sortedKeys),
                    try JSONSerialization.data(withJSONObject: generation[key] ?? [], options: .sortedKeys)
                )
            }
            let sentTools = try XCTUnwrap(generation["tools"] as? [[String: Any]])
            XCTAssertEqual(Set(sentTools.compactMap { $0["name"] as? String }), expectedNames)
            let serializedInput = try JSONSerialization.data(withJSONObject: generation["input"] ?? [])
            let visibleInput = String(decoding: serializedInput, as: UTF8.self)
            XCTAssertTrue(visibleInput.contains("Continue creating the SwiftUI iOS project."))
            XCTAssertTrue(visibleInput.contains("Prior observed project detail."))
            XCTAssertEqual(countRequest.httpMethod, "POST")
            XCTAssertEqual(countRequest.value(forHTTPHeaderField: "Authorization"), "Bearer offline-work-budget-key")
        }
    }

    private func capturedMessages(
        effort: AgentEffort,
        externalTools: [DevelopmentExternalTool]
    ) async throws -> [DevelopmentMessage] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronFullWorkBudget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let provider = VyronWorkBudgetTestProvider()
        let agent = DevelopmentAgent(
            client: provider, workspace: try DevelopmentWorkspace(rootURL: directory), onSubagentEvent: { _ in }
        )
        _ = try await agent.run(
            goal: "Continue creating the SwiftUI iOS project.", model: "gpt-6.1-sol",
            automaticModelSelection: false, effort: effort,
            conversationContext: String(repeating: "Prior observed project detail. ", count: 150),
            externalTools: externalTools, onEvent: { _ in }, approveCommand: { _ in false }
        )
        return await provider.messages
    }
}
