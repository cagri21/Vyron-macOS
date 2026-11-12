import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOllamaDevelopmentReplyRepairTests: XCTestCase {
    override func tearDown() {
        VyronOllamaDevelopmentRepairURLProtocol.state.reset()
        super.tearDown()
    }

    func testEmptyAndWhitespaceCompletionRepairOnceThenAcceptNativeTools() async throws {
        let call = DevelopmentToolCall(name: "list_files", arguments: ["limit": .number(10)], id: "native-list")
        let native = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", toolCalls: [call])
        )
        for content in ["", " \n\t"] {
            let empty = try VyronOllamaDevelopmentRepairFixture.reply(
                DevelopmentMessage(role: "assistant", content: content), reason: "stop"
            )
            VyronOllamaDevelopmentRepairURLProtocol.state.configure { attempt, _ in attempt == 1 ? empty : native }

            let step = try await VyronOllamaDevelopmentRepairFixture.client().developmentStep(
                model: VyronOllamaDevelopmentRepairFixture.model,
                messages: baseMessages
            )

            XCTAssertEqual(step.message.toolCalls, [call])
            XCTAssertEqual(step.message.content, "")
            XCTAssertEqual(VyronOllamaDevelopmentRepairURLProtocol.state.requests.count, 2)
        }
    }

    func testThinkingOnlyReplyRepairsWithoutReflectingPrivateThinking() async throws {
        let privateThinking = "PRIVATE_THINKING_MUST_NOT_ENTER_HISTORY"
        let first = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant"), thinking: privateThinking
        )
        let final = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", content: "A complete public answer.")
        )
        VyronOllamaDevelopmentRepairURLProtocol.state.configure { attempt, _ in attempt == 1 ? first : final }
        var settings = ModelSettings()
        settings.thinking = true

        let step = try await VyronOllamaDevelopmentRepairFixture.client(settings: settings).developmentStep(
            model: VyronOllamaDevelopmentRepairFixture.model, messages: baseMessages
        )

        XCTAssertEqual(step.message.content, "A complete public answer.")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(step.message), as: UTF8.self).contains(privateThinking))
        let requests = VyronOllamaDevelopmentRepairURLProtocol.state.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { !String(decoding: $0, as: UTF8.self).contains(privateThinking) })
        let retry = try VyronOllamaDevelopmentRepairFixture.messages(in: XCTUnwrap(requests.last))
        XCTAssertTrue(retry.contains { $0.role == "system" && $0.content.contains("previous model response") })
    }

    func testRepeatedEmptyCompletionsStopAfterTwoRequestsWithExistingError() async throws {
        let empty = try VyronOllamaDevelopmentRepairFixture.reply(DevelopmentMessage(role: "assistant"))
        VyronOllamaDevelopmentRepairURLProtocol.state.configure { _, _ in empty }

        do {
            _ = try await VyronOllamaDevelopmentRepairFixture.client().developmentStep(
                model: VyronOllamaDevelopmentRepairFixture.model, messages: baseMessages
            )
            XCTFail("Two unusable completions must retain the existing failure boundary.")
        } catch LocalAIError.invalidResponse(let message) {
            XCTAssertEqual(message, "The local model finished without an answer or a native tool call.")
        }

        XCTAssertEqual(VyronOllamaDevelopmentRepairURLProtocol.state.requests.count, 2)
    }

    func testLengthLimitedPartialAnswerIsRepairedInsteadOfReturnedAsComplete() async throws {
        let incomplete = "PARTIAL_UNFINISHED_RESPONSE"
        let first = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", content: incomplete), reason: "length"
        )
        let final = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", content: "The complete result.")
        )
        VyronOllamaDevelopmentRepairURLProtocol.state.configure { attempt, _ in attempt == 1 ? first : final }

        let step = try await VyronOllamaDevelopmentRepairFixture.client().developmentStep(
            model: VyronOllamaDevelopmentRepairFixture.model, messages: baseMessages
        )

        XCTAssertEqual(step.message.content, "The complete result.")
        let requests = VyronOllamaDevelopmentRepairURLProtocol.state.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(String(decoding: try XCTUnwrap(requests.last), as: UTF8.self).contains(incomplete))
    }

    func testRepairKeepsExactModelThinkingToolsAndExplicitGenerationLimits() async throws {
        let empty = try VyronOllamaDevelopmentRepairFixture.reply(DevelopmentMessage(role: "assistant"))
        let final = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", content: "The complete result.")
        )
        VyronOllamaDevelopmentRepairURLProtocol.state.configure { attempt, _ in attempt == 1 ? empty : final }
        var settings = ModelSettings()
        settings.contextTokens = 32_768
        settings.maxOutputTokens = 2_048
        settings.temperature = 0.3
        settings.topP = 0.75
        settings.thinking = true

        _ = try await VyronOllamaDevelopmentRepairFixture.client(settings: settings).developmentStep(
            model: VyronOllamaDevelopmentRepairFixture.model, messages: baseMessages, effort: .quick, mode: .plan
        )

        let requests = VyronOllamaDevelopmentRepairURLProtocol.state.requests
        XCTAssertEqual(requests.count, 2)
        let first = try VyronOllamaDevelopmentRepairFixture.fields(XCTUnwrap(requests.first))
        let retry = try VyronOllamaDevelopmentRepairFixture.fields(XCTUnwrap(requests.last))
        XCTAssertEqual(first["model"], .string(VyronOllamaDevelopmentRepairFixture.model))
        XCTAssertEqual(retry["model"], first["model"])
        XCTAssertEqual(first["think"], .bool(true))
        XCTAssertEqual(retry["think"], first["think"])
        XCTAssertEqual(retry["tools"], first["tools"])
        XCTAssertEqual(retry["options"], first["options"])
        guard case .object(let options)? = first["options"] else { return XCTFail("Missing request options.") }
        XCTAssertEqual(options["num_predict"], .number(2_048))
        XCTAssertEqual(options["temperature"], .number(0.3))
        XCTAssertEqual(options["top_p"], .number(0.75))
    }

    func testRepairRetainsCompletedToolEvidenceAndEveryUserGuidanceMessage() async throws {
        let empty = try VyronOllamaDevelopmentRepairFixture.reply(DevelopmentMessage(role: "assistant"))
        let final = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", content: "The existing resource is ready.")
        )
        VyronOllamaDevelopmentRepairURLProtocol.state.configure { attempt, _ in attempt == 1 ? empty : final }
        let call = DevelopmentToolCall(name: "mcp_create_fixture", arguments: [:], id: "completed-action")
        let evidence = "Created resource CREATED_RESOURCE_EXACT_42."
        let guidance = "Keep that exact resource and do not create another."
        let messages = baseMessages + [
            DevelopmentMessage(role: "assistant", toolCalls: [call]),
            DevelopmentMessage(role: "tool", content: evidence, toolName: call.function.name, toolCallID: call.id),
            DevelopmentMessage(role: "user", content: guidance)
        ]

        _ = try await VyronOllamaDevelopmentRepairFixture.client().developmentStep(
            model: VyronOllamaDevelopmentRepairFixture.model, messages: messages
        )

        let requests = VyronOllamaDevelopmentRepairURLProtocol.state.requests
        XCTAssertEqual(requests.count, 2)
        let retry = try VyronOllamaDevelopmentRepairFixture.messages(in: XCTUnwrap(requests.last))
        XCTAssertEqual(retry.filter { $0.role == "user" }.map(\.content), [baseMessages[1].content, guidance])
        XCTAssertTrue(retry.contains { $0.content.contains("CREATED_RESOURCE_EXACT_42") })
        XCTAssertTrue(retry.contains { $0.content.contains(call.function.name) || $0.toolName == call.function.name })
    }

    func testCancellationAtFirstResponseStopsBeforeRepairRequest() async throws {
        let empty = try VyronOllamaDevelopmentRepairFixture.reply(DevelopmentMessage(role: "assistant"))
        let client = try VyronOllamaDevelopmentRepairFixture.client()
        let messages = baseMessages
        let operation = Task {
            try await client.developmentStep(model: VyronOllamaDevelopmentRepairFixture.model, messages: messages)
        }
        VyronOllamaDevelopmentRepairURLProtocol.state.configure { _, _ in
            operation.cancel()
            return empty
        }

        switch await operation.result {
        case .success:
            XCTFail("Cancellation must stop the step before the repair request.")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "Unexpected cancellation error: \(error)")
        }
        XCTAssertEqual(VyronOllamaDevelopmentRepairURLProtocol.state.requests.count, 1)
    }

    func testHTTPDecodeAndMissingDoneFailuresAreNotRetried() async throws {
        let empty = try VyronOllamaDevelopmentRepairFixture.reply(DevelopmentMessage(role: "assistant"))
        VyronOllamaDevelopmentRepairURLProtocol.state.configure(status: 500) { _, _ in empty }
        do {
            _ = try await VyronOllamaDevelopmentRepairFixture.client().developmentStep(
                model: VyronOllamaDevelopmentRepairFixture.model, messages: baseMessages
            )
            XCTFail("HTTP errors must propagate without a repair request.")
        } catch {
            XCTAssertEqual(error as? ModelProviderError, .http(500))
        }
        XCTAssertEqual(VyronOllamaDevelopmentRepairURLProtocol.state.requests.count, 1)

        let malformed = Data("{malformed".utf8)
        VyronOllamaDevelopmentRepairURLProtocol.state.configure { _, _ in malformed }
        do {
            _ = try await VyronOllamaDevelopmentRepairFixture.client().developmentStep(
                model: VyronOllamaDevelopmentRepairFixture.model, messages: baseMessages
            )
            XCTFail("Malformed JSON must propagate without a repair request.")
        } catch {
            XCTAssertTrue(error is DecodingError || error is LocalAIError, "Unexpected decode error: \(error)")
        }
        XCTAssertEqual(VyronOllamaDevelopmentRepairURLProtocol.state.requests.count, 1)

        let missingDone = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", content: "Unconfirmed final response."), done: nil
        )
        VyronOllamaDevelopmentRepairURLProtocol.state.configure { _, _ in missingDone }
        do {
            _ = try await VyronOllamaDevelopmentRepairFixture.client().developmentStep(
                model: VyronOllamaDevelopmentRepairFixture.model, messages: baseMessages
            )
            XCTFail("An incomplete transport response must not use content repair.")
        } catch {
            XCTAssertEqual(error as? LocalAIError, .incompleteStream)
        }
        XCTAssertEqual(VyronOllamaDevelopmentRepairURLProtocol.state.requests.count, 1)
    }

    func testUnexpectedLifecycleCompletionDoesNotUseContentRepair() async throws {
        for reason in ["load", "unload", "unexpected"] {
            let empty = try VyronOllamaDevelopmentRepairFixture.reply(
                DevelopmentMessage(role: "assistant"), reason: reason
            )
            VyronOllamaDevelopmentRepairURLProtocol.state.configure { _, _ in empty }

            do {
                _ = try await VyronOllamaDevelopmentRepairFixture.client().developmentStep(
                    model: VyronOllamaDevelopmentRepairFixture.model, messages: baseMessages
                )
                XCTFail("Unexpected lifecycle replies must remain failures.")
            } catch LocalAIError.invalidResponse {
                XCTAssertEqual(VyronOllamaDevelopmentRepairURLProtocol.state.requests.count, 1)
            }
        }
    }

    private var baseMessages: [DevelopmentMessage] {
        [
            DevelopmentMessage(role: "system", content: "Keep the existing project execution restrictions."),
            DevelopmentMessage(role: "user", content: "Inspect the project and report the result.")
        ]
    }
}
