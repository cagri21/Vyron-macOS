import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOllamaThinkingControlTests: XCTestCase {
    func testSavedThinkingSettingDoesNotPreventChatWithANonThinkingModel() async throws {
        let client = try makeClient(thinking: true)
        let answer = try await chat(client, model: "plain:latest")
        XCTAssertEqual(answer, "omitted")

        // Reusing the client with a compatible model still applies the unchanged saved preference.
        let supportedAnswer = try await chat(client, model: "boolean:latest")
        XCTAssertEqual(supportedAnswer, "true")
    }

    func testMissingDiscoveryCapabilityChecksMetadataAndOmitsAnUnsupportedSavedSetting() async throws {
        let client = try makeClient(thinking: true)
        let answer = try await chat(client, model: "unknown:latest")
        XCTAssertEqual(answer, "omitted")
    }

    func testNamedLevelsKeepProviderDefaultsForBothSavedBooleanPreferences() async throws {
        for preference in [false, true] {
            let client = try makeClient(thinking: preference)
            let answer = try await chat(client, model: "named:latest")
            XCTAssertEqual(answer, "omitted")
            let support = try await client.thinkingControlSupport(
                for: LocalModel(name: "named:latest", size: 0, capabilities: ["thinking"])
            )
            XCTAssertEqual(support, .levels(VyronModelThinkingLevels(levels: [.low, .high])))
        }
    }

    func testBooleanControlsNeedBothAdvertisedValues() async throws {
        let client = try makeClient()
        let cases: [String: VyronModelThinkingSupport] = [
            "plain:latest": .unsupported,
            "boolean:latest": .boolean,
            "false-only:latest": .levels(VyronModelThinkingLevels(levels: [.low, .high], supportsOff: true)),
            "true-only:latest": .levels(VyronModelThinkingLevels(levels: [], supportsOn: true)),
            "off-only:latest": .levels(VyronModelThinkingLevels(levels: [], supportsOff: true)),
            "legacy:latest": .boolean,
            "qwen3.8:27b": .boolean
        ]
        for (model, expected) in cases {
            let support = try await client.thinkingControlSupport(for: LocalModel(name: model, size: 0))
            XCTAssertEqual(support, expected, model)
        }
    }

    func testPartialBooleanValuesPreserveSupportedRequestsAndOmitUnsupportedOnes() async throws {
        let enabledClient = try makeClient(thinking: true)
        let unsupportedAnswer = try await chat(enabledClient, model: "false-only:latest")
        XCTAssertEqual(unsupportedAnswer, "omitted")

        let disabledClient = try makeClient(thinking: false)
        let supportedAnswer = try await chat(disabledClient, model: "false-only:latest")
        XCTAssertEqual(supportedAnswer, "false")

        let defaultClient = try makeClient()
        let defaultAnswer = try await chat(defaultClient, model: "false-only:latest")
        XCTAssertEqual(defaultAnswer, "omitted")
    }

    func testAutomaticLeavesNativeDefaultsForBooleanNamedAndPartialModels() async throws {
        let client = try makeClient()
        for model in ["boolean:latest", "named:latest", "false-only:latest", "legacy:latest", "qwen3.8:27b"] {
            let answer = try await chat(client, model: model)
            XCTAssertEqual(answer, "omitted", model)
        }
    }

    func testAdvertisedNamedSubsetIsSentWithoutGuessingUnavailableLevels() async throws {
        for level in [VyronModelThinkingLevel.low, .high] {
            let client = try makeClient(level: level)
            let namedAnswer = try await chat(client, model: "named:latest")
            let mixedAnswer = try await chat(client, model: "false-only:latest")
            XCTAssertEqual(namedAnswer, level.rawValue)
            XCTAssertEqual(mixedAnswer, level.rawValue)
        }
        let unavailable = try makeClient(level: .medium)
        let unavailableAnswer = try await chat(unavailable, model: "named:latest")
        XCTAssertEqual(unavailableAnswer, "omitted")
        let unsupported = try makeClient(level: .high)
        let unsupportedAnswer = try await chat(unsupported, model: "plain:latest")
        let laterSupportedAnswer = try await chat(unsupported, model: "named:latest")
        XCTAssertEqual(unsupportedAnswer, "omitted")
        XCTAssertEqual(laterSupportedAnswer, "high")
    }

    func testUnknownNamedValuesPreserveDefaultsAndDoNotCreateControls() async throws {
        let client = try makeClient(level: .high)
        let support = try await client.thinkingControlSupport(
            for: LocalModel(name: "unknown-level:latest", size: 0)
        )
        XCTAssertEqual(support, .providerDefaultOnly)
        let namedAnswer = try await chat(client, model: "unknown-level:latest")
        XCTAssertEqual(namedAnswer, "omitted")
        let boolean = try makeClient(thinking: true)
        let booleanAnswer = try await chat(boolean, model: "unknown-level:latest")
        XCTAssertEqual(booleanAnswer, "omitted")
    }

    func testVerifiedMetadataOverridesAStaleDiscoveryCapabilityList() async throws {
        let client = try makeClient(level: .high)
        let support = try await client.thinkingControlSupport(
            for: LocalModel(name: "stale-caps:latest", size: 0, capabilities: ["tools"])
        )
        XCTAssertEqual(support, .levels(VyronModelThinkingLevels(levels: [.low, .high])))
        let answer = try await chat(client, model: "stale-caps:latest")
        XCTAssertEqual(answer, "high")
    }

    func testPartialBooleanControlsSendOnlyTheAdvertisedValue() async throws {
        for enabled in [false, true] {
            let client = try makeClient(thinking: enabled)
            let onOnly = try await chat(client, model: "true-only:latest")
            let offOnly = try await chat(client, model: "off-only:latest")
            XCTAssertEqual(onOnly, enabled ? "true" : "omitted")
            XCTAssertEqual(offOnly, enabled ? "omitted" : "false")
        }
    }

    func testSeparateNativeThinkingChunksNeverEnterVisibleAnswerTokens() async throws {
        for settings in [ModelSettings(thinking: true), namedSettings(.high)] {
            let recorder = VyronThinkingTokenRecorder()
            let client = try makeClient(settings: settings)
            let model = settings.thinkingLevel == nil ? "boolean:latest" : "named:latest"
            let expected = settings.thinkingLevel?.rawValue ?? "true"
            let answer = try await client.chat(
                model: model,
                messages: [ChatMessage(role: "user", content: "Hello")]
            ) { recorder.record($0) }
            XCTAssertEqual(answer, expected)
            XCTAssertEqual(recorder.tokens, [expected])
            let message = ChatMessage(role: "assistant", content: answer)
            XCTAssertFalse(String(decoding: try JSONEncoder().encode(message), as: UTF8.self)
                .contains("NATIVE_REASONING_MARKER"))
        }
    }

    func testMetadataErrorsAndCancellationAreNotReportedAsUnsupportedThinking() async throws {
        let client = try makeClient()
        do {
            _ = try await client.thinkingControlSupport(for: LocalModel(name: "metadata-failure:latest", size: 0))
            XCTFail("Expected the metadata failure to propagate")
        } catch {
            XCTAssertEqual(error as? ModelProviderError, .http(500))
        }
        do {
            _ = try await client.thinkingControlSupport(for: LocalModel(name: "cancelled-metadata:latest", size: 0))
            XCTFail("Expected cancellation to propagate")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testThinkingOnlyOrTruncatedDevelopmentRepliesCannotFinishTheTask() async throws {
        let client = try makeClient(level: .high)
        for model in ["step-empty:latest", "step-whitespace:latest", "step-length:latest", "step-truncated:latest"] {
            do {
                _ = try await client.developmentStep(
                    model: model,
                    messages: [DevelopmentMessage(role: "user", content: "Inspect the project")]
                )
                XCTFail("A thinking-only or truncated reply must not be a successful development step.")
            } catch let error as LocalAIError {
                guard case .invalidResponse(let message) = error else {
                    XCTFail("Expected an invalid final reply, got \(error)")
                    continue
                }
                XCTAssertFalse(message.isEmpty)
                XCTAssertFalse(message.contains("NATIVE_REASONING_MARKER"))
            }
        }
    }

    func testNativeToolCallsRemainValidWhenVisibleContentIsEmpty() async throws {
        let client = try makeClient(level: .high)
        let step = try await client.developmentStep(
            model: "step-call:latest",
            messages: [DevelopmentMessage(role: "user", content: "Inspect the project")]
        )
        XCTAssertEqual(step.message.content, "")
        XCTAssertEqual(step.message.toolCalls?.first?.function.name, "list_files")
        XCTAssertEqual(step.message.toolCalls?.count, 1)
    }

    private func makeClient(
        thinking: Bool? = nil,
        level: VyronModelThinkingLevel? = nil
    ) throws -> OllamaClient {
        var settings = ModelSettings(thinking: thinking)
        settings.thinkingLevel = level
        return try makeClient(settings: settings)
    }

    private func namedSettings(_ level: VyronModelThinkingLevel) -> ModelSettings {
        var settings = ModelSettings()
        settings.thinkingLevel = level
        return settings
    }

    private func makeClient(settings: ModelSettings) throws -> OllamaClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronOllamaThinkingURLProtocol.self]
        let profile = ModelConnectionProfile(
            name: "Thinking test",
            kind: .ollama,
            endpoint: "http://localhost:11434",
            selectedModel: "boolean:latest",
            settings: settings
        )
        return try OllamaClient(connection: profile, configuration: configuration)
    }

    private func chat(_ client: OllamaClient, model: String) async throws -> String {
        try await client.chat(model: model, messages: [ChatMessage(role: "user", content: "Hello")]) { _ in }
    }
}
