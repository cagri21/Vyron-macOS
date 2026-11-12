import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronVoiceModelTests: XCTestCase {
    func testDictationUpdatesDraftAndFinalDoesNotSend() async throws {
        let test = try VyronVoiceTestHarness()
        defer { test.cleanUp() }
        test.model.toggleDictation()
        try await test.waitUntil { test.model.phase == .listening }
        test.speech.sessions[0].onUpdate("A partial", false)
        XCTAssertEqual(test.conversation.drafts, ["A partial"])
        test.speech.sessions[0].onUpdate("A complete sentence", true)
        XCTAssertEqual(test.conversation.drafts.last, "A complete sentence")
        XCTAssertTrue(test.conversation.turns.isEmpty)
        XCTAssertEqual(test.model.phase, .idle)
        test.speech.sessions[0].onUpdate("late text", true)
        XCTAssertEqual(test.conversation.drafts.count, 2)
    }

    func testLiveTurnStopsMicrophoneSpeaksSelectedVoiceAndListensAgain() async throws {
        let test = try VyronVoiceTestHarness()
        defer { test.cleanUp() }
        test.model.selectedVoiceID = "voice-b"
        test.model.toggleLiveConversation()
        try await test.waitUntil { test.model.phase == .listening }
        let stops = test.speech.listeningStops
        test.speech.sessions[0].onUpdate("  Hello Vyron  ", true)
        XCTAssertEqual(test.conversation.turns, ["Hello Vyron"])
        XCTAssertEqual(test.model.phase, .thinking)
        XCTAssertGreaterThan(test.speech.listeningStops, stops)
        test.speech.sessions[0].onUpdate("duplicate final", true)
        XCTAssertEqual(test.conversation.turns.count, 1)
        test.model.responseFinished(answer: "Hello back", error: nil)
        XCTAssertEqual(test.model.phase, .speaking)
        XCTAssertEqual(test.speech.utterances.first?.voiceID, "voice-b")
        XCTAssertEqual(test.speech.utterances.first?.text, "Hello back")
        XCTAssertEqual(test.speech.sessions.count, 1)
        test.speech.utterances[0].onFinished()
        try await test.waitUntil { test.speech.sessions.count == 2 && test.model.phase == .listening }
        XCTAssertTrue(test.model.isLiveConversation)
    }

    func testSilenceSubmitsLatestPartialOnceAndStoppingCancelsDebounce() async throws {
        let test = try VyronVoiceTestHarness()
        defer { test.cleanUp() }
        test.model.toggleLiveConversation()
        try await test.waitUntil { test.model.phase == .listening }
        test.speech.sessions[0].onUpdate("First words", false)
        test.speech.sessions[0].onUpdate("First words with the rest", false)
        try await test.waitUntil { test.model.phase == .thinking }
        XCTAssertEqual(test.conversation.turns, ["First words with the rest"])
        test.model.end()
        test.model.toggleLiveConversation()
        try await test.waitUntil { test.model.phase == .listening }
        test.speech.sessions[1].onUpdate("Do not submit this", false)
        test.model.end()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(test.conversation.turns.count, 1)
        XCTAssertEqual(test.model.phase, .idle)
    }

    func testStopDuringPermissionIgnoresLateApprovalAndCallbacks() async throws {
        let test = try VyronVoiceTestHarness()
        defer { test.cleanUp() }
        test.speech.suspendPermission = true
        test.model.toggleLiveConversation()
        try await test.waitUntil { test.speech.sessions.count == 1 }
        XCTAssertEqual(test.model.phase, .requestingPermission)
        test.model.end()
        test.speech.grantPermission(0)
        test.speech.sessions[0].onUpdate("Stale capture", true)
        test.speech.sessions[0].onFailure("Stale failure")
        await Task.yield()
        XCTAssertEqual(test.model.phase, .idle)
        XCTAssertFalse(test.model.isLiveConversation)
        XCTAssertNil(test.model.errorMessage)
        XCTAssertTrue(test.conversation.turns.isEmpty)
    }

    func testStoppingSynthesisDoesNotRearmAndOldCompletionCannotStopNewPreview() async throws {
        let test = try VyronVoiceTestHarness()
        defer { test.cleanUp() }
        test.model.previewVoice()
        XCTAssertEqual(test.model.phase, .speaking)
        test.model.end()
        test.model.previewVoice()
        test.speech.utterances[0].onFinished()
        XCTAssertEqual(test.model.phase, .speaking)
        test.speech.utterances[1].onFinished()
        XCTAssertEqual(test.model.phase, .idle)
        XCTAssertTrue(test.speech.sessions.isEmpty)
    }

    func testRecognitionFailureCanRetryAndOldSessionCannotAffectRetry() async throws {
        let test = try VyronVoiceTestHarness()
        defer { test.cleanUp() }
        test.model.toggleLiveConversation()
        try await test.waitUntil { test.model.phase == .listening }
        test.speech.sessions[0].onFailure("Microphone unavailable")
        XCTAssertEqual(test.model.phase, .idle)
        XCTAssertEqual(test.model.errorMessage, "Microphone unavailable")
        test.model.retryLastSession()
        try await test.waitUntil { test.speech.sessions.count == 2 && test.model.phase == .listening }
        test.speech.sessions[0].onFailure("Old failure")
        test.speech.sessions[0].onUpdate("Old transcript", true)
        XCTAssertNil(test.model.errorMessage)
        XCTAssertTrue(test.conversation.turns.isEmpty)
        test.speech.sessions[1].onUpdate("Retry request", true)
        XCTAssertEqual(test.conversation.turns, ["Retry request"])
    }

    func testDictationRetryRetainsDictationMode() async throws {
        let test = try VyronVoiceTestHarness()
        defer { test.cleanUp() }
        test.model.toggleDictation()
        try await test.waitUntil { test.model.phase == .listening }
        test.speech.sessions[0].onFailure("Permission temporarily unavailable")
        test.model.retryLastSession()
        try await test.waitUntil { test.speech.sessions.count == 2 && test.model.phase == .listening }
        XCTAssertFalse(test.model.isLiveConversation)
        test.speech.sessions[1].onUpdate("A dictated retry", true)
        XCTAssertEqual(test.conversation.drafts, ["A dictated retry"])
        XCTAssertTrue(test.conversation.turns.isEmpty)
    }

    func testRepeatedUnchangedPartialsDoNotPostponeEndOfTurn() async throws {
        let test = try VyronVoiceTestHarness(silenceDelay: .milliseconds(40))
        defer { test.cleanUp() }
        test.model.toggleLiveConversation()
        try await test.waitUntil { test.model.phase == .listening }
        test.speech.sessions[0].onUpdate("Finished speaking", false)
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(10))
            test.speech.sessions[0].onUpdate("Finished speaking", false)
        }
        XCTAssertEqual(test.model.phase, .thinking)
        XCTAssertEqual(test.conversation.turns, ["Finished speaking"])
    }

    func testAIFailureEndsSessionWithoutSpeakingOrRearming() async throws {
        let test = try VyronVoiceTestHarness()
        defer { test.cleanUp() }
        test.model.toggleLiveConversation()
        try await test.waitUntil { test.model.phase == .listening }
        test.speech.sessions[0].onUpdate("A question", true)
        test.model.responseFinished(answer: nil, error: "Model disconnected")
        XCTAssertEqual(test.model.phase, .idle)
        XCTAssertEqual(test.model.errorMessage, "Model disconnected")
        XCTAssertFalse(test.model.isLiveConversation)
        XCTAssertTrue(test.speech.utterances.isEmpty)
        XCTAssertEqual(test.speech.sessions.count, 1)
    }

    func testInterruptCancelsThinkingOnceAndRejectsOldSpeechCompletion() async throws {
        let test = try VyronVoiceTestHarness()
        defer { test.cleanUp() }
        test.conversation.onCancel = { test.model.end(cancelResponse: false) }
        test.model.toggleLiveConversation()
        try await test.waitUntil { test.model.phase == .listening }
        test.speech.sessions[0].onUpdate("A question", true)
        test.model.interrupt()
        try await test.waitUntil { test.speech.sessions.count == 2 && test.model.phase == .listening }
        XCTAssertEqual(test.conversation.cancellations, 1)
        XCTAssertTrue(test.model.isLiveConversation)
        test.speech.sessions[1].onUpdate("Another question", true)
        test.model.responseFinished(answer: "An answer", error: nil)
        test.model.interrupt()
        try await test.waitUntil { test.speech.sessions.count == 3 && test.model.phase == .listening }
        test.speech.utterances[0].onFinished()
        XCTAssertEqual(test.model.phase, .listening)
        XCTAssertEqual(test.speech.sessions.count, 3)
        XCTAssertEqual(test.conversation.cancellations, 1)
    }

    func testVoiceChoicePersistsAndMissingVoiceFallsBackToSystemDefault() throws {
        let test = try VyronVoiceTestHarness()
        defer { test.cleanUp() }
        test.model.selectedVoiceID = "voice-b"
        let reopened = VyronVoiceModel(service: test.speech, defaults: test.defaults)
        XCTAssertEqual(reopened.selectedVoiceID, "voice-b")
        test.defaults.set("removed-voice", forKey: VyronUserDefaultsKey.selectedSpeechVoiceID.rawValue)
        let unavailable = VyronVoiceModel(service: test.speech, defaults: test.defaults)
        XCTAssertEqual(unavailable.selectedVoiceID, "")
    }

    func testRejectedStartAndRejectedTurnSurfaceErrorWithoutContinuing() async throws {
        let test = try VyronVoiceTestHarness()
        defer { test.cleanUp() }
        test.conversation.validationError = "Finish the current task"
        test.model.toggleLiveConversation()
        XCTAssertEqual(test.model.errorMessage, "Finish the current task")
        XCTAssertTrue(test.speech.sessions.isEmpty)
        test.conversation.validationError = nil
        test.conversation.acceptsTurns = false
        test.model.toggleLiveConversation()
        try await test.waitUntil { test.model.phase == .listening }
        test.speech.sessions[0].onUpdate("Cannot send", true)
        XCTAssertEqual(test.model.phase, .idle)
        XCTAssertNotNil(test.model.errorMessage)
        XCTAssertEqual(test.model.transcript, "Cannot send")
    }
}
