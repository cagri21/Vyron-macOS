import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronTerminalVisibilityTests: XCTestCase {
    func testCommandsAndQuestionKeepClosedTerminalClosed() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronTerminalTestProvider()
        try await startInspection(test, provider: provider)

        let question = try await waitForQuestion(test.model)

        XCTAssertFalse(test.model.inspector.showTerminal)
        assertRecordedCommand(test.model, count: 1)
        try await answerAndFinish(question, test: test)

        XCTAssertFalse(test.model.inspector.showTerminal)
        assertRecordedCommand(test.model, count: 2)
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertTrue(requests.last?.contains { $0.content.contains("Only this feature") } == true)
    }

    func testOpeningTerminalDuringQuestionRemainsOpenThroughFurtherCommandsAndCompletion() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        try await startInspection(test, provider: VyronTerminalTestProvider())
        let question = try await waitForQuestion(test.model)
        XCTAssertFalse(test.model.inspector.showTerminal)

        test.model.openWorkspaceTool(.terminal)

        XCTAssertTrue(test.model.inspector.showTerminal)
        XCTAssertEqual(test.model.interactions.pendingUserInput?.id, question.id)
        try await answerAndFinish(question, test: test)
        XCTAssertTrue(test.model.inspector.showTerminal)
        assertRecordedCommand(test.model, count: 2)
    }

    func testClosingTerminalDuringQuestionRemainsClosedThroughFurtherCommandsAndCompletion() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.model.inspector.showTerminal = true
        try await startInspection(test, provider: VyronTerminalTestProvider())
        let question = try await waitForQuestion(test.model)
        XCTAssertTrue(test.model.inspector.showTerminal)

        test.model.openWorkspaceTool(.terminal)

        XCTAssertFalse(test.model.inspector.showTerminal)
        XCTAssertEqual(test.model.interactions.pendingUserInput?.id, question.id)
        try await answerAndFinish(question, test: test)
        XCTAssertFalse(test.model.inspector.showTerminal)
        assertRecordedCommand(test.model, count: 2)
    }

    private func startInspection(
        _ test: VyronFeatureTestHarness,
        provider: VyronTerminalTestProvider
    ) async throws {
        test.select(test.profile(modelName: "terminal-test"), provider: provider, capabilities: ["tools"])
        test.model.skillContextLoader = { _ in .empty }
        test.model.computerWork.automaticRequestRouting = false
        await test.model.loadWorkspace(test.project)
        test.model.composer.mode = .agent
        test.model.composer.draft = "Inspect the installed Swift version, ask for the scope, then inspect it again."
        XCTAssertNil(test.model.errorMessage)
        XCTAssertTrue(test.model.canSend)
        test.model.send()
    }

    private func waitForQuestion(_ model: AppModel) async throws -> VyronUserInputRequest {
        try await waitUntil {
            model.interactions.pendingUserInput != nil
                && model.inspector.developmentEvents.contains { $0.kind == .commandFinished }
        }
        return try XCTUnwrap(model.interactions.pendingUserInput)
    }

    private func answerAndFinish(
        _ question: VyronUserInputRequest,
        test: VyronFeatureTestHarness
    ) async throws {
        test.model.respondToUserInput(VyronUserInputResponse(requestID: question.id, answers: [
            VyronUserInputAnswer(questionID: "scope", value: "Only this feature")
        ]))
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertNil(test.model.interactions.pendingUserInput)
        XCTAssertNil(test.model.errorMessage)
        XCTAssertTrue(test.model.messages.last?.content.contains("Finished the requested inspection.") == true)
    }

    private func assertRecordedCommand(_ model: AppModel, count: Int) {
        XCTAssertEqual(model.inspector.developmentEvents.filter { $0.kind == .commandStarted }.count, count)
        XCTAssertEqual(model.inspector.developmentEvents.filter { $0.kind == .commandFinished }.count, count)
        XCTAssertEqual(model.inspector.terminalOutput.components(separatedBy: "$ swift --version").count - 1, count)
        // Command execution can be refused by nested macOS protection; its actual output must still be retained.
        XCTAssertTrue(model.inspector.terminalOutput.contains("["))
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The terminal inspection did not reach the expected lifecycle state.")
        throw CancellationError()
    }
}
