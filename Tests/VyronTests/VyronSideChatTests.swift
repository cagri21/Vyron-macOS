import Foundation
import XCTest
@testable import Vyron
import VyronCore

@MainActor
final class VyronSideChatTests: XCTestCase {
    func testSideChatRunsAndSavesWithoutCancelingMainResponse() async throws {
        let harness = try VyronSideChatTestHarness()
        let model = harness.model
        let sourceID = try XCTUnwrap(model.selectedConversationID)
        model.composer.draft = "Continue the main conversation."
        model.send()
        try await harness.waitUntil { await harness.provider.requests.count == 1 }
        let generation = model.foregroundRun.activeGeneration
        let response = model.foregroundRun.activeResponse?.messageID
        let sideID = try XCTUnwrap(model.newSideChat(from: sourceID))
        let session = try XCTUnwrap(model.newSideChatSessions[sideID])
        XCTAssertEqual(model.selectedConversationID, sourceID)
        XCTAssertEqual(model.foregroundRun.activeGeneration, generation)
        XCTAssertEqual(model.foregroundRun.activeResponse?.messageID, response)
        XCTAssertTrue(model.foregroundRun.isGenerating)

        session.draft = "Explain the current task separately."
        session.send()
        try await harness.waitUntil { await harness.provider.requests.count == 2 }
        XCTAssertTrue(model.isSidebarConversationActive(sideID))
        XCTAssertFalse(model.canOpenSideChatInMain(sideID))
        await harness.provider.complete(2, answer: "Independent side answer")
        try await harness.waitUntil { !session.isGenerating }
        XCTAssertTrue(model.foregroundRun.isGenerating)
        XCTAssertEqual(model.foregroundRun.activeGeneration, generation)
        XCTAssertEqual(model.foregroundRun.activeResponse?.messageID, response)
        XCTAssertEqual(model.conversations.first(where: { $0.id == sideID })?.messages.last?.content,
            "Independent side answer")

        await harness.provider.complete(1, answer: "Main answer")
        try await harness.waitUntil { !model.foregroundRun.isGenerating }
        let reopened = AppModel(historyDirectory: harness.directory)
        XCTAssertEqual(reopened.conversations.first(where: { $0.id == sideID })?.mode, ComposerMode.chat.rawValue)
        XCTAssertEqual(reopened.conversations.first(where: { $0.id == sideID })?.messages.last?.activity?.state, .completed)
        XCTAssertEqual(reopened.conversations.first(where: { $0.id == sourceID })?.messages.last?.content, "Main answer")
        await harness.cleanUp()
    }

    func testCapturedModelAndSourceSnapshotStayBoundToSideChat() async throws {
        let harness = try VyronSideChatTestHarness()
        let model = harness.model
        let sourceID = try XCTUnwrap(model.selectedConversationID)
        let sideID = try XCTUnwrap(model.newSideChat(from: sourceID))
        let session = try XCTUnwrap(model.newSideChatSessions[sideID])
        let replacement = VyronSideChatTestProvider()
        model.modelSelection.configuredInferenceClient = replacement
        model.modelSelection.isConnected = false
        model.modelSelection.selectedModel = "replacement-model"
        model.modelSelection.models = [LocalModel(name: "replacement-model", size: 1)]
        model.modelSelection.isConnected = true
        let sourceIndex = try XCTUnwrap(model.conversations.firstIndex(where: { $0.id == sourceID }))
        model.conversations[sourceIndex].messages.append(ChatMessage(role: "assistant", content: "Later source change"))

        session.draft = "Use the captured context."
        session.send()
        try await harness.waitUntil { await harness.provider.requests.count == 1 }
        let capturedRequests = await harness.provider.requests
        let request = try XCTUnwrap(capturedRequests.first)
        XCTAssertEqual(request.model, "side-chat-test-model")
        XCTAssertTrue(request.messages.first?.content.contains("Keep the original task and its evidence intact.") == true)
        XCTAssertFalse(request.messages.contains { $0.content.contains("Later source change") })
        let replacementRequests = await replacement.requests
        XCTAssertEqual(replacementRequests.count, 0)
        await harness.provider.complete(1, answer: "Captured answer")
        try await harness.waitUntil { !session.isGenerating }
        let saved = try XCTUnwrap(model.conversations.first(where: { $0.id == sideID }))
        XCTAssertTrue(saved.contextByMessageID?.values.first?.contains("Keep the original task") == true)
        await harness.cleanUp()
    }

    func testStopAndLateProviderTokensCannotOverwriteNewerTurn() async throws {
        let harness = try VyronSideChatTestHarness()
        let model = harness.model
        let sourceID = try XCTUnwrap(model.selectedConversationID)
        let sideID = try XCTUnwrap(model.newSideChat(from: sourceID))
        let session = try XCTUnwrap(model.newSideChatSessions[sideID])
        session.draft = "First side request"
        session.send()
        try await harness.waitUntil { await harness.provider.requests.count == 1 }
        await harness.provider.emit("Partial answer", request: 1)
        try await harness.waitUntil {
            model.conversations.first(where: { $0.id == sideID })?.messages.last?.content == "Partial answer"
        }
        let stoppedResponse = try XCTUnwrap(session.activeResponse?.messageID)
        model.closeSideChatWindow(sideID)
        XCTAssertFalse(session.isGenerating)
        XCTAssertFalse(model.isSidebarConversationActive(sideID))
        session.draft = "Newer side request"
        session.send()
        try await harness.waitUntil { await harness.provider.requests.count == 2 }
        await harness.provider.emit(" stale token", request: 1)
        await harness.provider.complete(1, answer: "Stale completion")
        await harness.provider.complete(2, answer: "Newer answer")
        try await harness.waitUntil { !session.isGenerating }
        let messages = try XCTUnwrap(model.conversations.first(where: { $0.id == sideID })?.messages)
        XCTAssertEqual(messages.first(where: { $0.id == stoppedResponse })?.content, "Partial answer")
        XCTAssertEqual(messages.first(where: { $0.id == stoppedResponse })?.activity?.state, .stopped)
        XCTAssertEqual(messages.last?.content, "Newer answer")
        XCTAssertEqual(messages.last?.activity?.state, .completed)
        await harness.cleanUp()
    }

    func testFailedInitialSaveRollsBackCreationAndPreservesMainSelection() async throws {
        let harness = try VyronSideChatTestHarness()
        let model = harness.model
        let sourceID = try XCTUnwrap(model.selectedConversationID)
        let organization = model.sidebarState.sidebarOrganization
        try harness.makeHistoryUnwritable()
        XCTAssertNil(model.newSideChat(from: sourceID))
        XCTAssertEqual(model.conversations.map(\.id), [sourceID])
        XCTAssertEqual(model.sidebarState.sidebarOrganization, organization)
        XCTAssertEqual(model.selectedConversationID, sourceID)
        XCTAssertTrue(model.newSideChatSessions.isEmpty)
        await harness.cleanUp()
    }

    func testImmediateStopDoesNotStartProviderRequest() async throws {
        let harness = try VyronSideChatTestHarness()
        let model = harness.model
        let sourceID = try XCTUnwrap(model.selectedConversationID)
        let sideID = try XCTUnwrap(model.newSideChat(from: sourceID))
        let session = try XCTUnwrap(model.newSideChatSessions[sideID])
        session.draft = "Cancel before the request starts."
        session.send()
        let task = session.stop()
        for _ in 0..<10 { await Task.yield() }
        let requests = await harness.provider.requests
        await harness.provider.finishAll()
        await task?.value
        XCTAssertTrue(requests.isEmpty)
        XCTAssertFalse(session.isGenerating)
        XCTAssertEqual(model.conversations.first(where: { $0.id == sideID })?.messages.last?.activity?.state, .stopped)
        await harness.cleanUp()
    }

    func testFailedTurnSaveKeepsDraftAndDoesNotContactProvider() async throws {
        let harness = try VyronSideChatTestHarness()
        let model = harness.model
        let sourceID = try XCTUnwrap(model.selectedConversationID)
        let sideID = try XCTUnwrap(model.newSideChat(from: sourceID))
        let session = try XCTUnwrap(model.newSideChatSessions[sideID])
        try harness.makeHistoryUnwritable()
        session.draft = "Keep my unsaved draft."
        session.send()
        XCTAssertEqual(session.draft, "Keep my unsaved draft.")
        XCTAssertFalse(session.isGenerating)
        XCTAssertTrue(model.conversations.first(where: { $0.id == sideID })?.messages.isEmpty == true)
        XCTAssertNotNil(session.errorMessage)
        let requests = await harness.provider.requests
        XCTAssertEqual(requests.count, 0)
        await harness.cleanUp()
    }

    func testMainComposerAndDeletionCannotRaceRunningSideTurn() async throws {
        let harness = try VyronSideChatTestHarness()
        let model = harness.model
        let sourceID = try XCTUnwrap(model.selectedConversationID)
        let sideID = try XCTUnwrap(model.newSideChat(from: sourceID))
        let session = try XCTUnwrap(model.newSideChatSessions[sideID])
        model.selectConversation(sideID)
        session.draft = "Hold this side answer."
        session.send()
        try await harness.waitUntil { await harness.provider.requests.count == 1 }
        model.composer.draft = "Do not send a concurrent main turn."
        XCTAssertFalse(model.canSend)
        model.send()
        model.deleteConversation(sideID)
        XCTAssertNotNil(model.conversations.first(where: { $0.id == sideID }))
        XCTAssertTrue(session.isGenerating)
        let requests = await harness.provider.requests
        XCTAssertEqual(requests.count, 1)
        let messageID = try XCTUnwrap(session.activeResponse?.messageID)
        XCTAssertTrue(model.isResponseActivityLive(conversationID: sideID, messageID: messageID))
        await harness.provider.complete(1, answer: "Completed safely")
        try await harness.waitUntil { !session.isGenerating }
        XCTAssertTrue(model.canSend)
        model.deleteConversation(sideID)
        XCTAssertNil(model.newSideChatSessions[sideID])
        XCTAssertNil(model.conversations.first(where: { $0.id == sideID }))
        await harness.cleanUp()
    }

    func testProviderFailureAndShutdownInvalidateSideGeneration() async throws {
        let harness = try VyronSideChatTestHarness()
        let model = harness.model
        let sourceID = try XCTUnwrap(model.selectedConversationID)
        let sideID = try XCTUnwrap(model.newSideChat(from: sourceID))
        let session = try XCTUnwrap(model.newSideChatSessions[sideID])
        session.draft = "Fail this request."
        session.send()
        try await harness.waitUntil { await harness.provider.requests.count == 1 }
        await harness.provider.fail(1)
        try await harness.waitUntil { !session.isGenerating }
        XCTAssertEqual(model.conversations.first(where: { $0.id == sideID })?.messages.last?.activity?.state, .failed)
        XCTAssertNotNil(session.errorMessage)
        session.draft = "Stop on shutdown."
        session.send()
        try await harness.waitUntil { await harness.provider.requests.count == 2 }
        model.isShuttingDown = true
        let tasks = model.stopSideChatsForShutdown()
        XCTAssertEqual(tasks.count, 1)
        XCTAssertFalse(session.isGenerating)
        XCTAssertFalse(session.canSend)
        await harness.provider.emit("late shutdown token", request: 2)
        await harness.provider.complete(2, answer: "Late shutdown answer")
        for task in tasks { await task.value }
        XCTAssertEqual(model.conversations.first(where: { $0.id == sideID })?.messages.last?.activity?.state, .stopped)
        XCTAssertEqual(model.conversations.first(where: { $0.id == sideID })?.messages.last?.content, "")
        await harness.cleanUp()
    }

    func testEmptyAnswerFailsWithoutCompletingAndCanRetry() async throws {
        let harness = try VyronSideChatTestHarness()
        let model = harness.model
        let sourceID = try XCTUnwrap(model.selectedConversationID)
        let sideID = try XCTUnwrap(model.newSideChat(from: sourceID))
        let session = try XCTUnwrap(model.newSideChatSessions[sideID])
        session.draft = "Return a real answer."
        session.send()
        try await harness.waitUntil { await harness.provider.requests.count == 1 }
        await harness.provider.complete(1, answer: " \n ")
        try await harness.waitUntil { !session.isGenerating }
        XCTAssertEqual(model.conversations.first(where: { $0.id == sideID })?.messages.last?.activity?.state, .failed)
        XCTAssertEqual(session.errorMessage, VyronHeaderText.sideChatNoAnswer)
        session.draft = "Try again."
        XCTAssertTrue(session.canSend)
        await harness.cleanUp()
    }

    func testPendingMainQueueKeepsItsTurnBeforeSideComposer() async throws {
        let harness = try VyronSideChatTestHarness()
        let model = harness.model
        let sourceID = try XCTUnwrap(model.selectedConversationID)
        let sideID = try XCTUnwrap(model.newSideChat(from: sourceID))
        let session = try XCTUnwrap(model.newSideChatSessions[sideID])
        let index = try XCTUnwrap(model.conversations.firstIndex(where: { $0.id == sideID }))
        model.conversations[index].queuedMessages = [VyronQueuedMessage(content: "Existing queued follow-up")]
        session.draft = "Do not jump ahead of the saved queue."
        XCTAssertFalse(session.canSend)
        session.send()
        let requests = await harness.provider.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(model.conversations[index].messages.isEmpty)
        XCTAssertEqual(session.draft, "Do not jump ahead of the saved queue.")
        await harness.cleanUp()
    }

    func testSidebarSaveFailureDoesNotCreateHistoryOrSession() async throws {
        let harness = try VyronSideChatTestHarness()
        let model = harness.model
        let sourceID = try XCTUnwrap(model.selectedConversationID)
        let historyURL = harness.directory.appendingPathComponent("conversations.json")
        let previousHistory = try Data(contentsOf: historyURL)
        let previousOrganization = model.sidebarState.sidebarOrganization
        let sidebarURL = harness.directory.appendingPathComponent("sidebar.json")
        try FileManager.default.removeItem(at: sidebarURL)
        try FileManager.default.createDirectory(at: sidebarURL, withIntermediateDirectories: false)

        XCTAssertNil(model.newSideChat(from: sourceID))
        XCTAssertEqual(model.conversations.map(\.id), [sourceID])
        XCTAssertEqual(model.sidebarState.sidebarOrganization, previousOrganization)
        XCTAssertEqual(try Data(contentsOf: historyURL), previousHistory)
        XCTAssertTrue(model.newSideChatSessions.isEmpty)
        await harness.cleanUp()
    }

    func testOpenInMainPreservesDifferentMainDraftAndAttachments() async throws {
        let harness = try VyronSideChatTestHarness()
        let model = harness.model
        let sourceID = try XCTUnwrap(model.selectedConversationID)
        let sideID = try XCTUnwrap(model.newSideChat(from: sourceID))
        model.composer.draft = "An unsent main-window draft"
        XCTAssertFalse(model.canOpenSideChatInMain(sideID))
        XCTAssertFalse(model.openSideChatInMain(sideID))
        XCTAssertEqual(model.selectedConversationID, sourceID)
        XCTAssertEqual(model.composer.draft, "An unsent main-window draft")
        model.composer.draft = ""
        model.composerAttachments.attachedFiles = [AttachedFile(path: "README.md", content: "Preserve this selection")]
        XCTAssertFalse(model.openSideChatInMain(sideID))
        XCTAssertEqual(model.composerAttachments.attachedFiles.count, 1)
        model.composerAttachments.attachedFiles = []
        XCTAssertTrue(model.openSideChatInMain(sideID))
        XCTAssertEqual(model.selectedConversationID, sideID)
        await harness.cleanUp()
    }

    func testFinalSaveFailureRestoresOnlyEmptyDraftAndRetainsUnstreamedAnswer() async throws {
        for nextDraft in ["", "A newer draft that must be preserved."] {
            let harness = try VyronSideChatTestHarness()
            let model = harness.model
            let sourceID = try XCTUnwrap(model.selectedConversationID)
            let sideID = try XCTUnwrap(model.newSideChat(from: sourceID))
            let session = try XCTUnwrap(model.newSideChatSessions[sideID])
            let originalPrompt = "Recover this prompt if the final save fails."
            session.draft = originalPrompt
            session.send()
            try await harness.waitUntil { await harness.provider.requests.count == 1 }
            let responseID = try XCTUnwrap(session.activeResponse?.messageID)
            session.draft = nextDraft
            try harness.makeHistoryUnwritable()
            await harness.provider.complete(1, answer: "A complete answer delivered without streaming tokens.")
            try await harness.waitUntil { !session.isGenerating }

            XCTAssertEqual(session.draft, nextDraft.isEmpty ? originalPrompt : nextDraft)
            XCTAssertEqual(session.unsavedAnswer, "A complete answer delivered without streaming tokens.")
            XCTAssertEqual(session.errorMessage, VyronHeaderText.sideChatSaveFailed)
            XCTAssertNil(session.activeResponse)
            XCTAssertFalse(model.isResponseActivityLive(conversationID: sideID, messageID: responseID))
            let requests = await harness.provider.requests
            XCTAssertEqual(requests.count, 1)
            await harness.cleanUp()
        }
    }
}
