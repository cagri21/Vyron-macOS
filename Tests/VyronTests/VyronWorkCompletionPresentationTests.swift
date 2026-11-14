import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronWorkCompletionPresentationTests: XCTestCase {
    func testWorkCompletionKeepsConciseAnswerAndPersistsToolDetailsAcrossReopen() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronWorkCompletionTestProvider()
        test.select(test.profile(modelName: "completion-test"), provider: provider, capabilities: ["tools"])
        test.model.skillContextLoader = { _ in .empty }
        test.model.computerWork.automaticRequestRouting = false
        await test.model.loadWorkspace(test.project)
        test.model.composer.mode = .agent
        test.model.composer.draft = "Update the project notes, then inspect the installed Swift version."
        XCTAssertNil(test.model.errorMessage)
        XCTAssertTrue(test.model.canSend)

        test.model.send()
        try await waitForCompletion(test.model)

        XCTAssertNil(test.model.errorMessage)
        let answer = try XCTUnwrap(test.model.messages.last)
        let activity = try XCTUnwrap(answer.activity)
        XCTAssertEqual(answer.role, "assistant")
        XCTAssertEqual(answer.content, VyronWorkCompletionTestProvider.answer)
        XCTAssertEqual(activity.state, .completed)
        XCTAssertTrue(activity.entries.contains {
            $0.kind == .tool && $0.category == .edit && $0.detail == "README.md"
        })
        XCTAssertGreaterThanOrEqual(activity.entries.filter {
            $0.kind == .tool && $0.category == .command && $0.detail == "swift --version"
        }.count, 2)
        XCTAssertEqual(
            try String(contentsOf: test.project.appendingPathComponent("README.md"), encoding: .utf8),
            "Updated local project notes.\n"
        )
        let command = try XCTUnwrap(test.model.inspector.developmentEvents.first {
            $0.kind == .commandFinished && $0.command == "swift --version"
        })
        let output = try XCTUnwrap(command.content)
        XCTAssertFalse(output.isEmpty)
        XCTAssertTrue(test.model.inspector.terminalOutput.contains("$ swift --version\n"))
        // Nested execution protection may refuse the command; retain its actual output either way.
        XCTAssertTrue(test.model.inspector.terminalOutput.contains(output))

        let conversationID = try XCTUnwrap(test.model.selectedConversationID)
        let reviewed = try XCTUnwrap(test.model.selectedConversation?.changesByResponseID?[answer.id.uuidString]?.first)
        XCTAssertEqual(reviewed.changes.map(\.path), ["README.md"])
        XCTAssertEqual(reviewed.changes.first?.before, "A local test project.\n")
        XCTAssertEqual(reviewed.changes.first?.after, "Updated local project notes.\n")
        test.model.showChangeReview(
            conversationID: conversationID,
            workspacePath: reviewed.workspacePath,
            changes: reviewed.changes,
            selectedPath: "README.md"
        )
        XCTAssertTrue(test.model.isWorkspaceInspectorVisible)
        XCTAssertEqual(test.model.inspector.selectedReviewChange?.path, "README.md")

        test.model.openActivity(conversationID: conversationID, messageID: answer.id)
        XCTAssertEqual(test.model.trackedMessage, answer)
        XCTAssertEqual(test.model.trackedActivity, activity)

        let reopened = AppModel(historyDirectory: test.directory)
        let saved = try XCTUnwrap(reopened.conversations.first { $0.id == conversationID })
        XCTAssertEqual(saved.messages.last, answer)
        XCTAssertEqual(saved.changesByResponseID?[answer.id.uuidString]?.first?.changes.first?.id, reviewed.changes[0].id)
        XCTAssertFalse(reopened.foregroundRun.isGenerating)
        reopened.selectConversation(conversationID)
        reopened.openActivity(conversationID: conversationID, messageID: answer.id)
        XCTAssertEqual(reopened.trackedMessage?.content, VyronWorkCompletionTestProvider.answer)
        XCTAssertEqual(reopened.trackedActivity, activity)
    }

    private func waitForCompletion(_ model: AppModel) async throws {
        for _ in 0..<500 {
            if !model.foregroundRun.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The in-memory Work completion did not finish.")
        throw CancellationError()
    }
}
