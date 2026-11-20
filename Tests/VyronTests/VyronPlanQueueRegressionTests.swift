import Foundation
import XCTest
@testable import Vyron
import VyronCore

@MainActor
final class VyronPlanQueueRegressionTests: XCTestCase {
    func testPromptAddedDuringAQueuedPlanTurnRunsOnceAfterThatTurnCompletes() async throws {
        let test = try await makePlanHarness()
        defer { test.cleanUp() }
        test.send("Plan the first project review")
        try await waitUntil { await test.provider.developmentRequests.count == 1 }
        test.send("Plan the first queued follow-up")
        await completeTurn(0, in: test, answer: "The first project review is planned.")
        try await waitUntil { await test.provider.developmentRequests.count == 2 }

        test.send("Plan the next validation step")
        let queuedID = try XCTUnwrap(test.model.queuedMessages.first?.id)
        test.model.composer.draft = "Preserve this unsent Plan draft"
        await completeTurn(1, in: test, answer: "The first queued follow-up is planned.")
        try await waitUntil { await test.provider.developmentRequests.count == 3 }

        let requests = await test.provider.developmentRequests
        XCTAssertTrue(requests[2].contains { $0.content.contains("Plan the next validation step") })
        XCTAssertEqual(test.model.messages.filter { $0.id == queuedID }.count, 1)
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
        XCTAssertEqual(test.model.composer.draft, "Preserve this unsent Plan draft")
        await assertPlanDelivery(in: test, expectedRequests: 3)

        await completeTurn(2, in: test, answer: "The next validation step is planned.")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        let completedRequests = await test.provider.developmentRequests
        XCTAssertEqual(completedRequests.count, 3)
        XCTAssertEqual(test.model.messages.filter { $0.id == queuedID }.count, 1)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
    }

    func testSavingAnEditAfterAPlanTurnCompletesResumesTheEditedPromptInFIFOOrder() async throws {
        try await exerciseEditAfterPlanCompletion(save: true)
    }

    func testCancelingAnEditAfterAPlanTurnCompletesResumesTheOriginalPromptInFIFOOrder() async throws {
        try await exerciseEditAfterPlanCompletion(save: false)
    }

    private func exerciseEditAfterPlanCompletion(save: Bool) async throws {
        let test = try await makePlanHarness()
        defer { test.cleanUp() }
        test.send("Plan the existing project")
        try await waitUntil { await test.provider.developmentRequests.count == 1 }
        let original = "Plan the first queued request"
        let edited = "Plan the revised first request"
        let following = "Plan the second queued request"
        test.send(original)
        test.send(following)
        let headID = try XCTUnwrap(test.model.queuedMessages.first?.id)
        let followingID = try XCTUnwrap(test.model.queuedMessages.last?.id)
        test.model.composer.draft = "Preserve this Plan draft"
        test.model.editQueuedMessage(headID)
        test.model.composer.draft = edited

        await completeTurn(0, in: test, answer: "The existing project is planned.")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        await test.model.composer.queuedMessageDrainTask?.value
        let pausedRequests = await test.provider.developmentRequests
        XCTAssertEqual(pausedRequests.count, 1)
        XCTAssertEqual(test.model.queuedMessages.map(\.id), [headID, followingID])
        XCTAssertTrue(test.model.composer.isEditingQueuedMessage)

        if save {
            test.model.send()
        } else {
            test.model.composer.cancelQueuedMessageEdit()
        }
        try await waitUntil { await test.provider.developmentRequests.count == 2 }
        let expected = save ? edited : original
        let resumedRequests = await test.provider.developmentRequests
        XCTAssertTrue(resumedRequests[1].contains { $0.content.contains(expected) })
        XCTAssertFalse(resumedRequests[1].contains { $0.content.contains(following) })
        if !save {
            XCTAssertFalse(resumedRequests[1].contains { $0.content.contains(edited) })
        }
        XCTAssertEqual(test.model.messages.filter { $0.id == headID }.map(\.content), [expected])
        XCTAssertEqual(test.model.queuedMessages.map(\.id), [followingID])
        XCTAssertEqual(test.model.composer.draft, "Preserve this Plan draft")

        await completeTurn(1, in: test, answer: "The first queued request is planned.")
        try await waitUntil { await test.provider.developmentRequests.count == 3 }
        let followingRequests = await test.provider.developmentRequests
        XCTAssertTrue(followingRequests[2].contains { $0.content.contains(following) })
        XCTAssertEqual(test.model.messages.filter { $0.id == followingID }.count, 1)
        XCTAssertEqual(test.model.messages.filter { $0.id == headID }.count, 1)
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
        XCTAssertEqual(test.model.composer.draft, "Preserve this Plan draft")
        await assertPlanDelivery(in: test, expectedRequests: 3)
        await completeTurn(2, in: test, answer: "The second queued request is planned.")
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        let completedRequests = await test.provider.developmentRequests
        XCTAssertEqual(completedRequests.count, 3)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
    }

    private func makePlanHarness() async throws -> VyronQueueTestHarness {
        let test = VyronQueueTestHarness()
        test.model.computerWork.automaticRequestRouting = false
        test.model.skillContextLoader = { _ in .empty }
        let project = test.directory.appendingPathComponent("PlanProject", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("Read-only Plan queue fixture.\n".utf8)
            .write(to: project.appendingPathComponent("README.md"))
        await test.model.loadWorkspace(project)
        test.model.composer.mode = .plan
        return test
    }

    private func completeTurn(_ index: Int, in test: VyronQueueTestHarness, answer: String) async {
        await test.provider.completeDevelopment(
            index, message: DevelopmentMessage(role: "assistant", content: answer)
        )
    }

    private func assertPlanDelivery(in test: VyronQueueTestHarness, expectedRequests: Int) async {
        let modes = await test.provider.developmentModes
        let chatRequests = await test.provider.requests
        XCTAssertEqual(modes, Array(repeating: .plan, count: expectedRequests))
        XCTAssertTrue(chatRequests.isEmpty)
        XCTAssertEqual(test.model.composer.mode, .plan)
        XCTAssertEqual(test.model.selectedConversation?.mode, ComposerMode.plan.rawValue)
        XCTAssertTrue(test.model.composer.pendingSteeringIDs.isEmpty)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Plan queue delivery did not reach its expected state")
        throw CancellationError()
    }
}
