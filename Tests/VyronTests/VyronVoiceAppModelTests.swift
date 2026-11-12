import XCTest
@testable import Vyron

@MainActor
final class VyronVoiceAppModelTests: XCTestCase {
    func testLiveConversationStartsInChatWithoutProjectFromDefaultAgentMode() async throws {
        let test = try VyronVoiceAppTestHarness()
        defer { test.cleanUp() }
        test.model.composer.mode = .agent
        test.model.voice.toggleLiveConversation()
        try await test.waitUntil { test.model.voice.phase == .listening }
        XCTAssertEqual(test.model.composer.mode, .chat)
        XCTAssertNil(test.model.voice.errorMessage)
    }

    func testDictationPreservesDraftPrefixAndDoesNotSendUntilUserSubmits() async throws {
        let test = try VyronVoiceAppTestHarness()
        defer { test.cleanUp() }
        test.model.composer.draft = "Existing notes:"
        test.model.voice.toggleDictation()
        try await test.waitUntil { test.model.voice.phase == .listening }
        test.voiceTest.speech.sessions[0].onUpdate("spoken words", false)
        XCTAssertEqual(test.model.composer.draft, "Existing notes: spoken words")
        test.voiceTest.speech.sessions[0].onUpdate("spoken words completed", true)
        XCTAssertEqual(test.model.composer.draft, "Existing notes: spoken words completed")
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        let requests = await test.provider.requests.count
        XCTAssertEqual(requests, 0)
    }

    func testLiveStartRefusesExistingDraftAndPreservesIt() throws {
        let test = try VyronVoiceAppTestHarness()
        defer { test.cleanUp() }
        test.model.composer.draft = "Keep this draft"
        test.model.voice.toggleLiveConversation()
        XCTAssertEqual(test.model.composer.draft, "Keep this draft")
        XCTAssertEqual(test.model.voice.errorMessage, VyronVoiceText.draftRequired)
        XCTAssertFalse(test.model.voice.isActive)
        XCTAssertTrue(test.voiceTest.speech.sessions.isEmpty)
    }

    func testSpokenTurnUsesExistingProviderAndOnlyCompletedReplyIsSpoken() async throws {
        let test = try VyronVoiceAppTestHarness()
        defer { test.cleanUp() }
        test.model.voice.toggleLiveConversation()
        try await test.waitUntil { test.model.voice.phase == .listening }
        test.voiceTest.speech.sessions[0].onUpdate("What can you do?", true)
        try await test.waitUntil { await test.provider.requests.count == 1 }
        XCTAssertEqual(test.model.voice.phase, .thinking)
        XCTAssertTrue(test.voiceTest.speech.utterances.isEmpty)
        let request = await test.provider.requests[0]
        XCTAssertEqual(request.last?.content, "What can you do?")
        await test.provider.complete(0, answer: "I can help with your project.")
        try await test.waitUntil { test.model.voice.phase == .speaking }
        XCTAssertEqual(test.voiceTest.speech.utterances[0].text, "I can help with your project.")
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
        test.voiceTest.speech.utterances[0].onFinished()
        try await test.waitUntil { test.voiceTest.speech.sessions.count == 2 && test.model.voice.phase == .listening }
    }

    func testChangingChatStopsVoiceAndIgnoresStaleRecognitionAndPlayback() async throws {
        let test = try VyronVoiceAppTestHarness()
        defer { test.cleanUp() }
        test.model.voice.toggleLiveConversation()
        try await test.waitUntil { test.model.voice.phase == .listening }
        test.voiceTest.speech.sessions[0].onUpdate("A question", true)
        try await test.waitUntil { await test.provider.requests.count == 1 }
        await test.provider.complete(0, answer: "A completed answer")
        try await test.waitUntil { test.model.voice.phase == .speaking }
        let other = Conversation(title: "Other chat", workspacePath: nil)
        test.model.conversations.append(other)
        test.model.selectConversation(other.id)
        test.voiceTest.speech.utterances[0].onFinished()
        test.voiceTest.speech.sessions[0].onUpdate("Stale old chat words", true)
        XCTAssertEqual(test.model.voice.phase, .idle)
        XCTAssertFalse(test.model.voice.isLiveConversation)
        XCTAssertTrue(test.model.messages.isEmpty)
        XCTAssertEqual(test.model.composer.draft, "")
        XCTAssertEqual(test.voiceTest.speech.sessions.count, 1)
    }

    func testInterruptCancelsVoiceProviderRequestAndReturnsToListening() async throws {
        let test = try VyronVoiceAppTestHarness()
        defer { test.cleanUp() }
        test.model.voice.toggleLiveConversation()
        try await test.waitUntil { test.model.voice.phase == .listening }
        test.voiceTest.speech.sessions[0].onUpdate("A question", true)
        try await test.waitUntil { await test.provider.requests.count == 1 }
        test.model.voice.interrupt()
        try await test.waitUntil {
            let cancellations = await test.provider.cancellations
            return cancellations == 1 && test.model.voice.phase == .listening
        }
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertTrue(test.model.voice.isLiveConversation)
        XCTAssertEqual(test.voiceTest.speech.sessions.count, 2)
        XCTAssertTrue(test.voiceTest.speech.utterances.isEmpty)
        XCTAssertFalse(test.model.messages.contains { $0.content.contains("STALE_CANCELLED_TOKEN") })
    }
}
