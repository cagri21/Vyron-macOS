import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

private actor SuggestedQuestionsProvider: ModelProvider {
    var holdSuggestions: Bool
    var failAnswer: Bool
    private(set) var suggestionRequests = 0
    private(set) var suggestionCancellations = 0

    init(holdSuggestions: Bool = false, failAnswer: Bool = false) {
        self.holdSuggestions = holdSuggestions
        self.failAnswer = failAnswer
    }
    func models() async throws -> [LocalModel] { [LocalModel(name: "question-test", size: 1)] }
    func chat(model: String, messages: [ChatMessage], systemPrompt: String?, onToken: @escaping @Sendable (String) -> Void) async throws -> String {
        if systemPrompt?.contains("Generate suggested follow-up questions") == true {
            suggestionRequests += 1
            if holdSuggestions {
                do { try await Task.sleep(for: .seconds(60)) }
                catch { suggestionCancellations += 1; throw error }
            }
            return #"{"questions":["How can I test the cache expiration?","Can I change the cache duration?"]}"#
        }
        if failAnswer { throw ModelProviderError.connectionFailed }
        let answer = "The cache expires after one minute."
        onToken(answer)
        return answer
    }
    func developmentModel(model: String, automaticModelSelection: Bool, effort: AgentEffort) async throws -> LocalModel { throw ModelProviderError.unsupportedTools }
    func developmentStep(model: String, messages: [DevelopmentMessage], effort: AgentEffort, mode: DevelopmentMode) async throws -> DevelopmentStep { throw ModelProviderError.unsupportedTools }
}

@MainActor
final class AppModelSuggestedQuestionsTests: XCTestCase {
    @MainActor
    private struct Harness {
        let directory: URL
        let model: AppModel
        let provider: SuggestedQuestionsProvider
        let defaults: [VyronUserDefaultsKey: Any]
        static let defaultsKeys: [VyronUserDefaultsKey] = [
            .selectedLocalModel, .automaticModelSelection
        ]

        func cleanUp() {
            model.stopGeneration()
            try? FileManager.default.removeItem(at: directory)
            for key in Self.defaultsKeys {
                if let value = defaults[key] { UserDefaults.standard.set(value, forKey: key.rawValue) }
                else { UserDefaults.standard.removeObject(forKey: key.rawValue) }
            }
        }
    }

    private func harness(hold: Bool = false, fail: Bool = false) throws -> Harness {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VyronQuestionTests-\(UUID())")
        let defaults = Harness.defaultsKeys.reduce(into: [VyronUserDefaultsKey: Any]()) { values, key in
            values[key] = UserDefaults.standard.object(forKey: key.rawValue)
        }
        let model = AppModel(historyDirectory: directory)
        let provider = SuggestedQuestionsProvider(holdSuggestions: hold, failAnswer: fail)
        model.modelSelection.configuredInferenceClient = provider
        model.workspaceState.workspaceURL = nil
        model.composer.mode = .chat
        model.modelSelection.models = [LocalModel(name: "question-test", size: 1)]
        model.modelSelection.selectedModel = "question-test"
        model.modelSelection.automaticModelSelection = false
        model.modelSelection.isConnected = true
        return Harness(directory: directory, model: model, provider: provider, defaults: defaults)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The suggestion request did not reach its expected state")
        throw CancellationError()
    }

    func testCompletedAnswerGetsPersistedQuestionsAndSelectionPreservesDraft() async throws {
        let test = try harness()
        defer { test.cleanUp() }
        test.model.composer.draft = "Explain cache expiration"
        test.model.send()
        try await waitUntil { test.model.messages.last?.suggestedQuestions?.isEmpty == false }
        let answer = try XCTUnwrap(test.model.messages.last)
        let question = try XCTUnwrap(answer.suggestedQuestions?.first)
        XCTAssertEqual(answer.suggestedQuestions, [question], "Only the best follow-up is saved for the composer")
        XCTAssertEqual(test.model.composerSuggestion?.text, question)
        XCTAssertEqual(answer.activity?.state, .completed)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertNil(test.model.errorMessage)
        test.model.composer.draft = "My existing question"
        test.model.useSuggestedQuestion(question, messageID: answer.id)
        XCTAssertEqual(test.model.composer.draft, "My existing question")
        test.model.composer.draft = ""
        test.model.useSuggestedQuestion("An untrusted question?", messageID: answer.id)
        XCTAssertEqual(test.model.composer.draft, "")
        test.model.useSuggestedQuestion(question, messageID: answer.id)
        XCTAssertEqual(test.model.composer.draft, question)
        XCTAssertEqual(test.model.messages.count, 2, "Selecting a hint must not send it")
        let reopened = AppModel(historyDirectory: test.directory)
        XCTAssertEqual(reopened.conversations.first?.messages.last?.suggestedQuestions, answer.suggestedQuestions)
    }

    func testOptionalSuggestionRequestDoesNotBlockCompletedAnswerAndNewChatCancelsIt() async throws {
        let test = try harness(hold: true)
        defer { test.cleanUp() }
        test.model.composer.draft = "Explain cache expiration"
        test.model.send()
        try await waitUntil { await test.provider.suggestionRequests == 1 }
        let firstID = try XCTUnwrap(test.model.selectedConversationID)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
        XCTAssertNil(test.model.messages.last?.suggestedQuestions)
        test.model.newConversation()
        try await waitUntil { await test.provider.suggestionCancellations == 1 }
        XCTAssertNil(test.model.selectedConversationID)
        XCTAssertNil(test.model.conversations.first(where: { $0.id == firstID })?.messages.last?.suggestedQuestions)
    }

    func testFailedAnswerDoesNotRequestSuggestions() async throws {
        let test = try harness(fail: true)
        defer { test.cleanUp() }
        test.model.composer.draft = "Explain cache expiration"
        test.model.send()
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        let requests = await test.provider.suggestionRequests
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .failed)
        XCTAssertNil(test.model.messages.last?.suggestedQuestions)
    }
}
