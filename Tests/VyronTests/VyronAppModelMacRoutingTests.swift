import Foundation
import XCTest
@testable import Vyron
import VyronCore

@MainActor
final class VyronAppModelMacRoutingTests: XCTestCase {
    func testChatTransfersExactMacRequestWithoutCallingTheChatProvider() async throws {
        let test = try configuredHarness()
        defer { test.cleanUp() }
        test.model.composer.draft = "  Can you open Safari?  "
        XCTAssertTrue(test.model.canSend)
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let goal = try XCTUnwrap(test.model.computerWork.pendingAgentGoal)
        XCTAssertEqual(goal.goal, "Can you open Safari?")
        XCTAssertEqual(goal.conversationID, test.model.selectedConversationID)
        XCTAssertEqual(goal.messageID, test.model.messages.last?.id)
        XCTAssertTrue(test.model.computerWork.isComputerWorkActive)
        XCTAssertTrue(test.model.appNavigation.showAutomation)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .working)
        let chatRequests = await test.provider.chatRequests
        XCTAssertEqual(chatRequests, 0)
    }

    func testCompletionFinishesActivityAndReleasesTheComposer() async throws {
        let test = try configuredHarness()
        defer { test.cleanUp() }
        let goal = try await transferGoal(test)
        let beforeStaleReport = test.model.messages.last?.content
        test.model.reportAgentProgress(requestID: UUID(), state: "Stale result", trace: [], finished: true)
        XCTAssertTrue(test.model.computerWork.isComputerWorkActive)
        XCTAssertEqual(test.model.messages.last?.content, beforeStaleReport)

        test.model.reportAgentProgress(
            requestID: goal.id, state: "Safari is open", trace: ["Opened Safari"], finished: true
        )

        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
        XCTAssertFalse(test.model.computerWork.isComputerWorkActive)
        XCTAssertFalse(test.model.computerWork.isPlanningControls)
        XCTAssertNil(test.model.computerWork.pendingAgentGoal)
        XCTAssertFalse(test.model.canStartAgentGoal(goal.id))
        test.model.composer.draft = "Hello"
        XCTAssertTrue(test.model.canSend)
    }

    func testSimulatorRequestInWorkUsesSelectedModelWithNativeToolsAndProjectContextIntact() async throws {
        let test = try configuredHarness()
        defer { test.cleanUp() }
        let provider = VyronMacWorkRoutingTestProvider()
        test.model.modelSelection.configuredInferenceClient = provider
        test.model.skillContextLoader = { _ in .empty }
        await test.model.loadWorkspace(test.project)
        test.model.composer.mode = .agent
        test.model.composer.draft = "Open Simulator"
        XCTAssertFalse(test.model.workspaceState.isLoadingWorkspace)
        XCTAssertNil(test.model.errorMessage)

        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        XCTAssertNil(test.model.computerWork.pendingAgentGoal)
        XCTAssertFalse(test.model.computerWork.isComputerWorkActive)
        XCTAssertFalse(test.model.appNavigation.showAutomation)
        XCTAssertEqual(test.model.workspaceState.workspaceURL, test.project)
        XCTAssertEqual(test.model.composer.mode, .agent)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
        let names = await provider.toolNames
        XCTAssertTrue(names.contains("vyron_mac_apps"))
        XCTAssertTrue(names.contains("vyron_mac_screenshot"))
        let models = await provider.requestedModels
        XCTAssertEqual(models, ["control-test"])
    }

    func testRemoteWorkModelReceivesNativeAppToolsWithoutLocalModelHandoff() async throws {
        let test = try configuredHarness()
        defer { test.cleanUp() }
        let provider = VyronMacWorkRoutingTestProvider()
        test.select(test.profile(modelName: "remote-tool-model", endpoint: "https://models.example.com/v1"),
                    provider: provider, capabilities: ["tools"])
        test.model.skillContextLoader = { _ in .empty }
        await test.model.loadWorkspace(test.project)
        test.model.composer.mode = .agent
        test.model.composer.draft = "Open Simulator"

        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        XCTAssertNil(test.model.computerWork.pendingAgentGoal)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
        let names = await provider.toolNames
        XCTAssertTrue(names.contains("vyron_mac_apps"))
        XCTAssertTrue(names.contains("vyron_mac_windows"))
        let models = await provider.requestedModels
        XCTAssertEqual(models, ["remote-tool-model"])
    }

    func testPlanProvidesNativeObservationsWithoutAppMutationTools() async throws {
        let test = try configuredHarness()
        defer { test.cleanUp() }
        let provider = VyronMacWorkRoutingTestProvider()
        test.model.modelSelection.configuredInferenceClient = provider
        test.model.skillContextLoader = { _ in .empty }
        await test.model.loadWorkspace(test.project)
        test.model.composer.mode = .plan
        test.model.composer.draft = "Inspect Simulator"

        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let names = await provider.toolNames
        XCTAssertTrue(names.contains("vyron_mac_apps"))
        XCTAssertTrue(names.contains("vyron_mac_inspect"))
        XCTAssertTrue(names.contains("vyron_mac_screenshot"))
        XCTAssertFalse(names.contains("vyron_mac_open_app"))
        XCTAssertFalse(names.contains("vyron_mac_open_project"))
        XCTAssertFalse(names.contains("vyron_mac_click"))
        XCTAssertFalse(names.contains("vyron_mac_type_text"))
        XCTAssertFalse(names.contains("vyron_mac_press_key"))
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
    }

    func testStopFinishesActivityAsStoppedAndIgnoresLateMacReports() async throws {
        let test = try configuredHarness()
        defer { test.cleanUp() }
        let goal = try await transferGoal(test)
        var stoppedController = false
        test.model.computerWork.stopAutomation = { stoppedController = true }
        test.model.stopGeneration()

        XCTAssertTrue(stoppedController)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .stopped)
        XCTAssertFalse(test.model.computerWork.isComputerWorkActive)
        XCTAssertNil(test.model.computerWork.pendingAgentGoal)
        let stoppedContent = test.model.messages.last?.content
        test.model.reportAgentProgress(
            requestID: goal.id, state: "Late controller result", trace: [], finished: true
        )
        XCTAssertEqual(test.model.messages.last?.activity?.state, .stopped)
        XCTAssertEqual(test.model.messages.last?.content, stoppedContent)
        test.model.composer.draft = "Hello"
        XCTAssertTrue(test.model.canSend)
    }

    func testRemoteModelDoesNotTransferAComputerTaskOrCallItsProvider() async throws {
        let test = try configuredHarness()
        defer { test.cleanUp() }
        let profile = test.profile(endpoint: "https://models.example.com/v1")
        test.select(profile, provider: test.provider)
        test.model.composer.draft = "Open Safari"
        XCTAssertTrue(test.model.canSend)
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        XCTAssertFalse(test.model.computerWork.isComputerWorkActive)
        XCTAssertNil(test.model.computerWork.pendingAgentGoal)
        XCTAssertFalse(test.model.appNavigation.showAutomation)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .failed)
        XCTAssertFalse(test.model.messages.last?.content.isEmpty ?? true)
        let chatRequests = await test.provider.chatRequests
        XCTAssertEqual(chatRequests, 0)
        test.model.composer.draft = "Hello"
        XCTAssertTrue(test.model.canSend)
    }

    func testOversizedMacGoalFailsWithoutBlockingTheNextMessage() async throws {
        let test = try configuredHarness()
        defer { test.cleanUp() }
        test.model.composer.draft = "Open Safari " + String(repeating: "x", count: 3_001)
        XCTAssertTrue(test.model.canSend)
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        XCTAssertFalse(test.model.computerWork.isComputerWorkActive)
        XCTAssertNil(test.model.computerWork.pendingAgentGoal)
        XCTAssertFalse(test.model.appNavigation.showAutomation)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .failed)
        let chatRequests = await test.provider.chatRequests
        XCTAssertEqual(chatRequests, 0)
        test.model.composer.draft = "Hello"
        XCTAssertTrue(test.model.canSend)
    }

    private func configuredHarness() throws -> VyronFeatureTestHarness {
        let test = try VyronFeatureTestHarness()
        test.model.modelSelection.activeConnectionID = nil
        test.model.modelSelection.connectionProfiles = []
        test.model.modelSelection.configuredInferenceClient = test.provider
        test.model.modelSelection.models = [LocalModel(name: "control-test", size: 1)]
        test.model.modelSelection.selectedModel = "control-test"
        test.model.modelSelection.automaticModelSelection = false
        test.model.computerWork.automaticRequestRouting = true
        test.model.modelSelection.isConnected = true
        return test
    }

    private func transferGoal(_ test: VyronFeatureTestHarness) async throws -> PendingAgentGoal {
        test.model.composer.draft = "Open Safari"
        XCTAssertTrue(test.model.canSend)
        test.model.send()
        try await test.waitUntil { test.model.computerWork.pendingAgentGoal != nil }
        return try XCTUnwrap(test.model.computerWork.pendingAgentGoal)
    }
}
