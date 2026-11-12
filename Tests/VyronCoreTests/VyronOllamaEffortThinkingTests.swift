import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOllamaEffortThinkingTests: XCTestCase {
    func testOnlyVerifiedAdvertisedNativeLevelsAreSelectedWithoutInventingHigherStrings() {
        let supported = VyronModelThinkingSupport.levels(VyronModelThinkingLevels(levels: [.low, .medium, .high]))
        XCTAssertNil(VyronOllamaEffortThinking.level(for: .automatic, support: supported))
        XCTAssertEqual(VyronOllamaEffortThinking.level(for: .quick, support: supported), .low)
        XCTAssertEqual(VyronOllamaEffortThinking.level(for: .balanced, support: supported), .medium)
        for effort in [AgentEffort.deep, .extraHigh, .maximum, .ultra] {
            XCTAssertEqual(VyronOllamaEffortThinking.level(for: effort, support: supported), .high)
        }
        let partial = VyronModelThinkingSupport.levels(VyronModelThinkingLevels(levels: [.high]))
        XCTAssertNil(VyronOllamaEffortThinking.level(for: .quick, support: partial))
        XCTAssertNil(VyronOllamaEffortThinking.level(for: .balanced, support: partial))
        XCTAssertEqual(VyronOllamaEffortThinking.level(for: .ultra, support: partial), .high)
        for support in [VyronModelThinkingSupport.unverified, .boolean, .unsupported, .providerDefaultOnly] {
            for effort in AgentEffort.allCases {
                XCTAssertNil(VyronOllamaEffortThinking.level(for: effort, support: support))
            }
        }
    }

    func testActualChatAndDevelopmentWireUseCachedAdvertisedLevelsAndOmitUnavailableMedium() async throws {
        let client = try client()
        let support = try await client.thinkingControlSupport(for: LocalModel(name: "named:latest", size: 0))
        XCTAssertEqual(support, .levels(VyronModelThinkingLevels(levels: [.low, .high])))
        let efforts: [AgentEffort] = [.automatic, .quick, .balanced, .deep, .extraHigh, .maximum, .ultra]
        let expected = ["omitted", "low", "omitted", "high", "high", "high", "high"]
        for (effort, value) in zip(efforts, expected) {
            let answer = try await chat(client, model: "named:latest", effort: effort)
            XCTAssertEqual(answer, value)
            let step = try await client.developmentStep(
                model: "named:latest", messages: [DevelopmentMessage(role: "user", content: "Inspect this project.")],
                effort: effort
            )
            XCTAssertEqual(step.message.content, value)
            XCTAssertFalse(answer.contains("NATIVE_REASONING_MARKER"))
        }
    }

    func testManualEffortDoesNotInventNativeControlBeforeVerification() async throws {
        let client = try client()
        let unverified = try await chat(client, model: "named:latest", effort: .ultra)
        XCTAssertEqual(unverified, "omitted")
        _ = try await client.thinkingControlSupport(for: LocalModel(name: "named:latest", size: 0))
        let verified = try await chat(client, model: "named:latest", effort: .ultra)
        XCTAssertEqual(verified, "high")
    }

    func testExplicitSavedNativePreferencesTakePrecedenceOverManualEffort() async throws {
        var named = ModelSettings()
        named.thinkingLevel = .low
        let namedClient = try client(settings: named)
        let namedAnswer = try await chat(namedClient, model: "named:latest", effort: .ultra)
        XCTAssertEqual(namedAnswer, "low")
        for enabled in [false, true] {
            let booleanClient = try client(settings: ModelSettings(thinking: enabled))
            for effort in [AgentEffort.quick, .ultra] {
                let answer = try await chat(booleanClient, model: "boolean:latest", effort: effort)
                XCTAssertEqual(answer, enabled ? "true" : "false")
            }
        }
        let defaults = try client()
        for model in ["plain:latest", "unknown-level:latest", "boolean:latest"] {
            _ = try await defaults.thinkingControlSupport(for: LocalModel(name: model, size: 0))
            let answer = try await chat(defaults, model: model, effort: .ultra)
            XCTAssertEqual(answer, "omitted")
        }
    }

    private func client(settings: ModelSettings = ModelSettings()) throws -> OllamaClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronOllamaThinkingURLProtocol.self]
        let profile = ModelConnectionProfile(
            name: "Offline effort thinking fixture", kind: .ollama,
            endpoint: "http://localhost:11434", selectedModel: "named:latest", settings: settings
        )
        return try OllamaClient(connection: profile, configuration: configuration)
    }

    private func chat(_ client: OllamaClient, model: String, effort: AgentEffort) async throws -> String {
        try await VyronChatInference.response(
            using: client,
            request: VyronChatInferenceRequest(
                model: model, messages: [ChatMessage(role: "user", content: "Hello")],
                configuration: VyronChatInferenceConfiguration(systemPrompt: nil, effort: effort)
            ),
            onToken: { _ in }
        )
    }
}
