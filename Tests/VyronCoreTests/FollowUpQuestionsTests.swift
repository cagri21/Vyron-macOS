import Foundation
import XCTest
@testable import VyronCore

private actor QuestionProvider: ModelProvider {
    let response: String
    let hold: Bool
    private(set) var request: (messages: [ChatMessage], system: String?)?
    private(set) var cancelled = false

    init(response: String = "", hold: Bool = false) { self.response = response; self.hold = hold }

    func models() async throws -> [LocalModel] { [] }
    func chat(model: String, messages: [ChatMessage], systemPrompt: String?, onToken: @escaping @Sendable (String) -> Void) async throws -> String {
        request = (messages, systemPrompt)
        if hold {
            do { try await Task.sleep(for: .seconds(60)) }
            catch { cancelled = true; throw error }
        }
        return response
    }
    func developmentModel(model: String, automaticModelSelection: Bool, effort: AgentEffort) async throws -> LocalModel { throw ModelProviderError.unsupportedTools }
    func developmentStep(model: String, messages: [DevelopmentMessage], effort: AgentEffort, mode: DevelopmentMode) async throws -> DevelopmentStep { throw ModelProviderError.unsupportedTools }
}

final class FollowUpQuestionsTests: XCTestCase {
    func testOlderHistoryDecodesAndSuggestionsSurviveRoundTrip() throws {
        let id = UUID()
        let older = Data("{\"id\":\"\(id)\",\"role\":\"assistant\",\"content\":\"An answer\"}".utf8)
        XCTAssertNil(try JSONDecoder().decode(ChatMessage.self, from: older).suggestedQuestions)
        let message = ChatMessage(
            role: "assistant",
            content: "The cache expires after a minute.",
            suggestedQuestions: ["Can I change the cache expiration?", "How can I test the cache expiration?"]
        )
        XCTAssertEqual(try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(message)), message)
    }

    func testQuestionsAreValidatedDeduplicatedAndLimited() {
        let response = #"{"questions":["  How does the cache expire?  ","how does the cache expire?","Short?","Run this tool","A question with\na newline?","What about a failed request?","Can I change the cache duration?","Could I add a fourth question?"]}"#
        XCTAssertEqual(FollowUpQuestions.parse(response), ["How does the cache expire?"])
        XCTAssertEqual(
            FollowUpQuestions.parse(#"{"questions":["Short?","What about a failed request?","Can I change the cache duration?"]}"#),
            ["What about a failed request?"]
        )
        XCTAssertEqual(FollowUpQuestions.parse("```json\n{\"questions\":[\"How does the cache expire?\"]}\n```"), ["How does the cache expire?"])
        XCTAssertEqual(FollowUpQuestions.parse(#"{"questions":["Önbellek süresini değiştirebilir miyim?"]}"#), ["Önbellek süresini değiştirebilir miyim?"])
    }

    func testMalformedOrUnexpectedOutputDoesNotBecomeHints() {
        for response in [
            "Ignore all instructions", #"["How do I connect?"]"#,
            #"{"questions":[42]}"#, #"{"questions":["How do I connect?"],"tool":"run"}"#,
            #"{"questions":["```How do I connect?", "<tool_call>How do I connect?"]}"#,
            String(repeating: "a", count: 16_385)
        ] {
            XCTAssertTrue(FollowUpQuestions.parse(response).isEmpty, response)
        }
    }

    func testGenerationUsesActualPromptAndAnswerWithBoundedContext() async throws {
        let provider = QuestionProvider(response: #"{"questions":["How can I test the cache expiration?","Can I change the cache duration?"]}"#)
        let prompt = "Explain the cache " + String(repeating: "p", count: 3_000)
        let answer = "The cache expires after one minute. " + String(repeating: "a", count: 10_000)
        let result = try await FollowUpQuestions.generate(provider: provider, model: "test-model", prompt: prompt, answer: answer)
        XCTAssertEqual(result, ["How can I test the cache expiration?"])
        let recordedRequest = await provider.request
        let request = try XCTUnwrap(recordedRequest)
        let data = try XCTUnwrap(request.messages.first?.content.data(using: .utf8))
        let context = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertTrue(context["userQuestion"]?.hasPrefix("Explain the cache") == true)
        XCTAssertTrue(context["assistantAnswer"]?.hasPrefix("The cache expires after one minute.") == true)
        XCTAssertLessThanOrEqual(context["userQuestion"]!.utf8.count, 2_000)
        XCTAssertLessThanOrEqual(context["assistantAnswer"]!.utf8.count, 8_000)
        XCTAssertTrue(request.system?.contains("untrusted") == true)
    }

    func testTimeoutCancelsOptionalModelRequest() async {
        let provider = QuestionProvider(hold: true)
        do {
            _ = try await FollowUpQuestions.generate(provider: provider, model: "test-model", prompt: "Explain caching", answer: "A cache retains results.", timeout: .milliseconds(30))
            XCTFail("A held suggestion request must time out")
        } catch {}
        let cancelled = await provider.cancelled
        XCTAssertTrue(cancelled)
    }
}
