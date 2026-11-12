import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronOpenAIResponsesStreamingTests: XCTestCase {
    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testStreamingHandlesFragmentedUnicodeMultilineEventsAndKeepsReasoningPrivate() async throws {
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            let body = try VyronResponsesTestSupport.body(request)
            XCTAssertEqual(request.url?.path, "/v1/responses")
            XCTAssertEqual(body["stream"] as? Bool, true)
            XCTAssertEqual(body["store"] as? Bool, false)
            XCTAssertEqual(body["max_output_tokens"] as? Int, 512)
            XCTAssertNil(body["reasoning"], "Normal requests preserve the provider's reasoning default")
            XCTAssertNil(body["temperature"])
            XCTAssertNil(body["top_p"])
            let terminal = try VyronResponsesTestSupport.json([
                "type": "response.completed", "response": [
                    "status": "completed", "output": [VyronResponsesTestSupport.textOutput("Hello 世界")]
                ]
            ])
            let stream = ": heartbeat\r\n\r\n"
                + "event: response.reasoning_summary_text.delta\r\n"
                + "data: {\"type\":\"response.reasoning_summary_text.delta\",\"delta\":\"private\"}\r\n\r\n"
                + "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hello \"}\r\n\r\n"
                + "data: {\"type\":\"response.output_text.delta\",\n"
                + "data: \"delta\":\"世界\"}\n\n"
                + "data: " + terminal + "\n\n"
            return VyronResponsesTestResponse(body: stream, fragmentBytes: 1)
        }
        let client = try VyronResponsesTestSupport.client(settings: ModelSettings(
            maxOutputTokens: 512
        ))
        let result = try await client.chat(
            model: "gpt-6.1-sol", messages: [ChatMessage(role: "user", content: "Hello")]
        ) { token in
            XCTAssertFalse(token.contains("private"))
        }
        XCTAssertEqual(result, "Hello 世界")
    }

    func testFailureIncompleteAndTruncationDoNotReturnPartialAnswersAsSuccess() async throws {
        let partial = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Partial\"}\n\n"
        let endings = [
            "",
            "data: {\"type\":\"response.failed\",\"response\":{\"status\":\"failed\",\"error\":{\"message\":\"private server detail\"}}}\n\n",
            "data: {\"type\":\"response.incomplete\",\"response\":{\"status\":\"incomplete\",\"incomplete_details\":{\"reason\":\"max_output_tokens\"}}}\n\n",
            "data: {\"type\":\"error\",\"message\":\"private server detail\"}\n\n"
        ]
        for ending in endings {
            await VyronResponsesTestURLProtocol.state.reset { _, _ in
                VyronResponsesTestResponse(body: partial + ending)
            }
            let client = try VyronResponsesTestSupport.client()
            do {
                _ = try await client.chat(
                    model: "gpt-6.1-sol", messages: [ChatMessage(role: "user", content: "Hi")]
                ) { _ in }
                XCTFail("An unfinished stream must not be reported as successful")
            } catch {
                XCTAssertTrue(error is ModelProviderError)
                XCTAssertFalse(error.localizedDescription.contains("private server detail"))
            }
        }
    }

    func testCompletedResponseStillRejectsAnEmptyVisibleAnswer() async throws {
        await VyronResponsesTestURLProtocol.state.reset { _, _ in
            VyronResponsesTestResponse(body:
                "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":[]}}\n\n"
            )
        }
        let client = try VyronResponsesTestSupport.client()
        do {
            _ = try await client.chat(
                model: "gpt-6.1-sol", messages: [ChatMessage(role: "user", content: "Hi")]
            ) { _ in }
            XCTFail("Reasoning or terminal metadata alone is not a visible answer")
        } catch {
            guard case .invalidResponse = error as? ModelProviderError else {
                return XCTFail("Expected invalid response, received \(error)")
            }
        }
    }

    func testCommentaryOnlyCompletedStreamDoesNotBecomeAFinalAnswer() async throws {
        var commentary = VyronResponsesTestSupport.textOutput("I will inspect the project.")
        commentary["phase"] = "commentary"
        let terminal = try VyronResponsesTestSupport.json([
            "type": "response.completed", "response": ["status": "completed", "output": [commentary]]
        ])
        let stream = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"I will inspect the project.\"}\n\n"
            + "data: " + terminal + "\n\n"
        await VyronResponsesTestURLProtocol.state.reset { _, _ in
            VyronResponsesTestResponse(body: stream)
        }
        let client = try VyronResponsesTestSupport.client()
        do {
            _ = try await client.chat(
                model: "gpt-6.1-sol", messages: [ChatMessage(role: "user", content: "Inspect")]
            ) { _ in }
            XCTFail("Interim commentary must not masquerade as a completed answer")
        } catch {
            guard case .invalidResponse = error as? ModelProviderError else {
                return XCTFail("Expected an invalid response, received \(error)")
            }
        }
    }

    func testCancellationStopsTheStreamingRequestAndRemainsCancellation() async throws {
        await VyronResponsesTestURLProtocol.state.reset { _, _ in
            VyronResponsesTestResponse(
                body: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Started\"}\n\n",
                holdOpen: true
            )
        }
        let client = try VyronResponsesTestSupport.client()
        let tokens = VyronResponsesTestTokens()
        let task = Task {
            try await client.chat(
                model: "gpt-6.1-sol", messages: [ChatMessage(role: "user", content: "Hi")]
            ) { token in
                Task { await tokens.append(token) }
            }
        }
        for _ in 0..<1_000 {
            if await tokens.values.contains("Started") { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let streamed = await tokens.values
        XCTAssertTrue(streamed.contains("Started"))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled stream must not succeed")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        for _ in 0..<1_000 {
            if await VyronResponsesTestURLProtocol.state.stopCount > 0 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let stopped = await VyronResponsesTestURLProtocol.state.stopCount
        XCTAssertGreaterThan(stopped, 0)
    }

    func testHTTPFailuresNeverExposeTheAPIKeyOrServerBody() async throws {
        await VyronResponsesTestURLProtocol.state.reset { _, _ in
            VyronResponsesTestResponse(
                body: #"{"error":{"message":"offline-test-key private response body"}}"#, statusCode: 403
            )
        }
        let client = try VyronResponsesTestSupport.client()
        do {
            _ = try await client.chat(
                model: "gpt-6.1-sol", messages: [ChatMessage(role: "user", content: "Hi")]
            ) { _ in }
            XCTFail("Expected the server access rejection")
        } catch {
            XCTAssertEqual(error as? ModelProviderError, .http(403))
            XCTAssertFalse(error.localizedDescription.contains("offline-test-key"))
            XCTAssertFalse(error.localizedDescription.contains("private response body"))
        }
    }
}
