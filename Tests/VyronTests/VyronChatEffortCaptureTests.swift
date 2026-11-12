import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronChatEffortCaptureTests: XCTestCase {
    func testMainChatDispatchUsesEffortCapturedBeforeItsTaskStarts() async throws {
        let test = try VyronSideChatTestHarness()
        addTeardownBlock { await test.cleanUp() }
        test.model.composer.effort = .extraHigh
        let selectedModel = test.model.modelSelection.selectedModel
        test.model.composer.draft = "Explain the current task."
        test.model.send()
        test.model.composer.effort = .ultra
        try await test.waitUntil { await test.provider.effortRequests.count == 1 }
        let requests = await test.provider.effortRequests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.configuration.effort, .extraHigh)
        XCTAssertEqual(request.model, selectedModel)
        XCTAssertEqual(request.messages.last?.content, "Explain the current task.")
        XCTAssertEqual(test.model.composer.effort, .ultra)
        await test.provider.complete(1, answer: "The captured effort answer.")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertEqual(test.model.modelSelection.selectedModel, selectedModel)
        XCTAssertEqual(test.model.composer.effort, .ultra)
    }

    func testSideSessionRetainsCreationEffortAcrossLaterMainSelectionAndMultipleTurns() async throws {
        let test = try VyronSideChatTestHarness()
        addTeardownBlock { await test.cleanUp() }
        test.model.composer.effort = .maximum
        let sourceID = try XCTUnwrap(test.model.selectedConversationID)
        let sideID = try XCTUnwrap(test.model.newSideChat(from: sourceID))
        let session = try XCTUnwrap(test.model.newSideChatSessions[sideID])
        XCTAssertEqual(session.configuration.effort, .maximum)
        let selectedModel = test.model.modelSelection.selectedModel
        test.model.composer.effort = .quick
        session.draft = "First independent question."
        session.send()
        try await test.waitUntil { await test.provider.effortRequests.count == 1 }
        await test.provider.complete(1, answer: "First independent answer.")
        try await test.waitUntil { !session.isGenerating }
        test.model.composer.effort = .automatic
        session.draft = "Second independent question."
        session.send()
        try await test.waitUntil { await test.provider.effortRequests.count == 2 }
        let captured = await test.provider.effortRequests
        XCTAssertEqual(captured.map { $0.configuration.effort }, [.maximum, .maximum])
        XCTAssertEqual(captured.map(\.model), [selectedModel, selectedModel])
        XCTAssertEqual(test.model.selectedConversationID, sourceID)
        XCTAssertEqual(test.model.composer.effort, .automatic)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        await test.provider.complete(2, answer: "Second independent answer.")
        try await test.waitUntil { !session.isGenerating }
    }

    func testScheduledChatUsesSavedEffortInsteadOfLaterMainSelection() async throws {
        let test = try VyronScheduledAppModelTestHarness()
        let provider = VyronSideChatTestProvider()
        addTeardownBlock {
            await provider.finishAll()
            try await test.cleanUp()
        }
        test.model.modelSelection.configuredInferenceClient = provider
        test.model.composer.effort = .ultra
        let task = test.task()
        XCTAssertTrue(test.model.scheduledTasks.save(task))
        test.model.composer.effort = .quick
        test.model.scheduledTasks.runNow(task.id)
        for _ in 0..<500 {
            if await provider.effortRequests.count == 1 { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        let requests = await provider.effortRequests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.configuration.effort, .ultra)
        XCTAssertEqual(request.model, task.definition.context.model.model)
        XCTAssertEqual(request.messages.last?.content, task.definition.prompt)
        XCTAssertEqual(test.model.composer.effort, .quick)
        await provider.complete(1, answer: "The saved effort scheduled answer.")
        await test.model.scheduledTasks.waitForCurrentRun()
        XCTAssertEqual(test.model.composer.effort, .quick)
        XCTAssertEqual(test.model.composer.draft, "Keep this unsent draft.")
    }
}
