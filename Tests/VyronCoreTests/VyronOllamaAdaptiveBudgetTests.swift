import Foundation
import XCTest
import VyronModelDomain
import VyronDevelopment
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOllamaAdaptiveBudgetTests: XCTestCase {
    override func tearDown() {
        VyronDevelopmentBudgetURLProtocol.state.configure(nil)
        super.tearDown()
    }

    func testUltraReservesItsFullOutputAndGrowsOnlyWithinVerifiedContext() throws {
        let request = request(bytes: 24_500, effort: .ultra)
        let allocation = try VyronOllamaDevelopmentBudget.allocation(
            for: request, settings: ModelSettings(), maximumContext: 131_072, toolBytes: 4_000
        )
        XCTAssertEqual(allocation.contextTokens, 65_536)
        XCTAssertEqual(allocation.outputTokens, 12_288)
        XCTAssertGreaterThan(allocation.messageBudget.maximumBytes, 24_000)
        XCTAssertLessThanOrEqual(
            allocation.messageBudget.maximumBytes + 4_000 + 2_048 + allocation.outputTokens,
            allocation.contextTokens
        )
    }

    func testExplicitContextAndSmallRuntimeLimitsRemainHardBoundaries() throws {
        for settings in [ModelSettings(contextTokens: 32_768), ModelSettings()] {
            XCTAssertThrowsError(try VyronOllamaDevelopmentBudget.allocation(
                for: request(bytes: 24_500, effort: .ultra), settings: settings,
                maximumContext: 32_768, toolBytes: 4_000
            )) { XCTAssertEqual($0 as? DevelopmentAgentError, .contextBudget) }
        }
        XCTAssertThrowsError(try VyronOllamaDevelopmentBudget.allocation(
            for: request(bytes: 100, effort: .balanced), settings: ModelSettings(contextTokens: 65_536),
            maximumContext: 32_768, toolBytes: 4_000
        ))
    }

    func testExplicitOutputAndSmallQuickContextArePreserved() throws {
        let allocation = try VyronOllamaDevelopmentBudget.allocation(
            for: request(bytes: 100, effort: .quick),
            settings: ModelSettings(maxOutputTokens: 512), maximumContext: 131_072, toolBytes: 1_000
        )
        XCTAssertEqual(allocation.contextTokens, 16_384)
        XCTAssertEqual(allocation.outputTokens, 512)
    }

    func testUltraUsesOnlyTheHighestAdvertisedThinkingLevel() {
        let medium = VyronModelThinkingSupport.levels(VyronModelThinkingLevels(levels: [.low, .medium]))
        XCTAssertEqual(VyronOllamaEffortThinking.level(for: .ultra, support: medium), .medium)
        XCTAssertEqual(VyronOllamaEffortThinking.level(
            for: .ultra, support: .levels(VyronModelThinkingLevels(levels: [.low, .high]))
        ), .high)
        XCTAssertNil(VyronOllamaEffortThinking.level(for: .ultra, support: .unverified))
        XCTAssertNil(VyronOllamaEffortThinking.level(for: .ultra, support: .providerDefaultOnly))
    }

    func testLargeRepositoryGuidanceReachesActualOllamaDispatchWithUltra() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VyronBudget-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let guidance = String(repeating: "Retain saved connections and scope.\n", count: 405)
        try Data(guidance.utf8).write(to: root.appendingPathComponent("AGENTS.md"))
        VyronDevelopmentBudgetURLProtocol.state.configure { request in
            switch request.url?.path {
            case "/api/tags":
                return Data(#"{"models":[{"name":"qwen3-coder:30b","size":19000000000,"capabilities":["tools"]}]}"#.utf8)
            case "/api/show":
                return Data(#"{"capabilities":["tools"],"thinking":{"values":[false]},"model_info":{"qwen3.context_length":131072}}"#.utf8)
            case "/api/chat":
                return Data(#"{"done":true,"message":{"role":"assistant","content":"Read-only plan completed."}}"#.utf8)
            default: throw URLError(.unsupportedURL)
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronDevelopmentBudgetURLProtocol.self]
        let endpoint = try XCTUnwrap(URL(string: "http://127.0.0.1:11434"))
        let client = OllamaClient(baseURL: endpoint, configuration: configuration)
        let result = try await DevelopmentAgent(client: client, workspace: DevelopmentWorkspace(rootURL: root)).run(
            goal: "Analyze the code and propose a read-only plan.", model: "qwen3-coder:30b",
            effort: .ultra, mode: .plan, onEvent: { _ in }, approveCommand: { _ in false }
        )
        XCTAssertTrue(result.isComplete)
        let request = try XCTUnwrap(VyronDevelopmentBudgetURLProtocol.state.requests.last {
            $0.url?.path == "/api/chat"
        })
        let body = try Self.body(request)
        let options = try XCTUnwrap(body["options"] as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let context = try XCTUnwrap(options["num_ctx"] as? Int)
        let output = try XCTUnwrap(options["num_predict"] as? Int)
        XCTAssertEqual(output, 12_288)
        XCTAssertGreaterThan(context, 32_768)
        XCTAssertTrue(messages.contains { ($0["content"] as? String)?.contains(guidance) == true })
        let input = try JSONSerialization.data(withJSONObject: messages).count
            + JSONSerialization.data(withJSONObject: XCTUnwrap(body["tools"])).count
        XCTAssertLessThanOrEqual(input + output + 2_048, context)
    }

    func testPlanInstructionsPreserveReadOnlyBoundariesWithoutWorkOnlyInstructions() {
        let text = VyronDevelopmentPlanInstructions.text
        XCTAssertLessThan(text.utf8.count, 3_000)
        XCTAssertTrue(text.contains("read-only"))
        XCTAssertTrue(text.contains("never edit/create/move/delete"))
        XCTAssertTrue(text.contains("Truncated excerpts and bounded inventories are incomplete"))
        XCTAssertTrue(text.contains("without private reasoning"))
    }

    private func request(bytes: Int, effort: AgentEffort) -> VyronDevelopmentBudgetRequest {
        VyronDevelopmentBudgetRequest(
            model: LocalModel(name: "qwen3-coder:30b", size: 19_000_000_000),
            configuration: VyronDevelopmentInferenceConfiguration(effort: effort, mode: .plan, externalTools: []),
            minimumMessageBytes: bytes
        )
    }

    private static func body(_ request: URLRequest) throws -> [String: Any] {
        if let body = request.httpBody {
            return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
