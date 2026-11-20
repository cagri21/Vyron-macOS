import Foundation
import XCTest
@testable import Vyron
import VyronModelDomain

@MainActor
final class VyronAutoLocalAppRoutingTests: XCTestCase {
    func testLocalChoiceContinuesChatWithoutBuildingAConnectedProvider() async throws {
        let test = try VyronAutoLocalAppTestHarness()
        defer { test.cleanUp() }

        test.send("Explain this function")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let requests = await test.assessment.requests
        let builds = await test.assessment.providerBuilds
        let models = await test.local.chatModels
        let efforts = await test.local.efforts
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.assessor.name, "qwen3:4b")
        XCTAssertTrue(builds.isEmpty)
        XCTAssertEqual(models, ["qwen3:4b"])
        XCTAssertEqual(efforts.first, .deep)
        XCTAssertEqual(test.model.messages.last?.content, "Auto Local answer")
    }

    func testConnectedChoiceUsesRecentContextAndPreservesSavedSelection() async throws {
        let test = try VyronAutoLocalAppTestHarness()
        defer { test.cleanUp() }
        await test.assessment.select(test.profile.id.uuidString)
        var conversation = Conversation(title: "Existing context", workspacePath: nil)
        conversation.mode = ComposerMode.chat.rawValue
        conversation.messages = [
            ChatMessage(role: .user, content: "The system must retain old records."),
            ChatMessage(role: .assistant, content: "I will preserve storage compatibility.")
        ]
        test.model.conversations = [conversation]
        test.model.selectedConversationID = conversation.id

        test.send("Analyze the migration with those constraints")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let assessmentRequests = await test.assessment.requests
        let request = try XCTUnwrap(assessmentRequests.first)
        let builds = await test.assessment.providerBuilds
        let models = await test.hosted.chatModels
        let localModels = await test.local.chatModels
        XCTAssertTrue(request.context.messages.contains { $0.content.contains("retain old records") })
        XCTAssertEqual(builds, [test.profile.id])
        XCTAssertEqual(models, [test.profile.selectedModel])
        XCTAssertTrue(localModels.isEmpty)
        XCTAssertNil(test.model.modelSelection.activeConnectionID)
        XCTAssertEqual(test.model.modelSelection.selectedModel, "qwen3:4b")
        XCTAssertEqual(test.model.modelSelection.connectionProfiles, [test.profile])
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
    }

    func testExplicitEffortTakesPrecedenceOverTheAssessment() async throws {
        let test = try VyronAutoLocalAppTestHarness()
        defer { test.cleanUp() }
        test.model.composer.effort = .quick

        test.send("Use my selected effort")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let efforts = await test.local.efforts
        XCTAssertEqual(efforts.first, .quick)
    }

    func testStopDuringAssessmentPreventsLateConnectedExecution() async throws {
        let test = try VyronAutoLocalAppTestHarness()
        defer { test.cleanUp() }
        await test.assessment.select(test.profile.id.uuidString)
        await test.assessment.hold()

        test.send("Investigate this difficult task")
        try await test.waitUntil { await test.assessment.requests.count == 1 }
        test.model.stopGeneration()
        let pending = test.model.foregroundRun.shutdown()
        await test.assessment.release()
        for task in pending { await task.value }

        let builds = await test.assessment.providerBuilds
        let models = await test.hosted.chatModels
        XCTAssertTrue(builds.isEmpty)
        XCTAssertTrue(models.isEmpty)
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .stopped)
    }

    func testAssessmentErrorIsVisibleAndNextTurnCanRetry() async throws {
        let test = try VyronAutoLocalAppTestHarness()
        defer { test.cleanUp() }
        await test.assessment.fail(.invalidResponse("Invalid local assessment"))

        test.send("First attempt")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertEqual(test.model.messages.last?.activity?.state, .failed)
        XCTAssertNotNil(test.model.errorMessage)
        await test.assessment.fail(nil)
        test.send("Retry the assessment")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
        let requests = await test.assessment.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testWorkCanUseAConnectedModelWithOnlyALocalAssessorInstalled() async throws {
        let test = try VyronAutoLocalAppTestHarness()
        defer { test.cleanUp() }
        let project = test.directory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("A test project.\n".utf8).write(to: project.appendingPathComponent("README.md"))
        await test.model.loadWorkspace(project)
        test.model.composer.mode = .agent
        await test.assessment.select(test.profile.id.uuidString)

        test.send("Inspect the project and explain its structure")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let models = await test.hosted.developmentModels
        let selections = await test.hosted.automaticSelections
        let efforts = await test.hosted.efforts
        XCTAssertEqual(models, [test.profile.selectedModel])
        XCTAssertEqual(selections, [false])
        XCTAssertEqual(efforts.first, .deep)
        XCTAssertEqual(test.model.messages.last?.content, "Auto Local work answer")
    }
}
