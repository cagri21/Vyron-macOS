import Foundation
import XCTest
@testable import Vyron
@testable import VyronAutomation
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

    func testRemoteChatOpensPhotosAfterAWorkActionEvenWhenSwitchingToWork() async throws {
        let test = try configuredHarness()
        defer { test.cleanUp() }
        let model = test.model
        test.select(test.profile(endpoint: "https://models.example.com/v1"), provider: test.provider)
        model.skillContextLoader = { _ in .empty }
        let controller = VyronMacWorkTestController()
        let photos = DesktopApplication(
            id: "com.apple.Photos", name: "Photos", bundleIdentifier: "com.apple.Photos", processIdentifier: 43
        )
        controller.catalog = [photos]
        controller.running = [photos]
        model.computerWork.macWorkController = controller

        let pendingWork = AsyncStream<Void>.makeStream()
        defer {
            pendingWork.continuation.finish()
            _ = model.foregroundRun.shutdown()
        }
        let work = startBackgroundWork(in: model, waitingOn: pendingWork.stream)
        let releaseMutation = AsyncStream<Void>.makeStream()
        var mutationStarted = false
        var mutationFinished = false
        let workMutation = Task {
            try await model.computerWork.macActions.perform {
                mutationStarted = true
                for await _ in releaseMutation.stream {}
                mutationFinished = true
            }
        }
        defer {
            releaseMutation.continuation.finish()
            workMutation.cancel()
        }
        try await test.waitUntil { mutationStarted }

        var focusCount = 0
        controller.onActivate = { [weak model] in
            XCTAssertEqual(model?.foregroundRun.response(in: work.conversationID), work)
            XCTAssertTrue(mutationFinished)
            focusCount += 1
        }

        model.composer.draft = "open photos app"
        XCTAssertTrue(model.canSend)
        model.send()
        let photoChat = try XCTUnwrap(model.foregroundRun.activeResponse)
        try await test.waitUntil {
            model.messages.last?.activity?.entries.contains {
                $0.title == VyronControlText.startingComputerTask
            } == true
        }
        XCTAssertEqual(focusCount, 0)
        model.selectConversation(work.conversationID, loadProject: false)
        XCTAssertEqual(model.foregroundRun.activeResponse, work)
        XCTAssertEqual(model.foregroundRun.response(in: photoChat.conversationID), photoChat)

        releaseMutation.continuation.finish()
        try await workMutation.value
        try await test.waitUntil { !model.foregroundRun.owns(photoChat) }

        XCTAssertEqual(focusCount, 1)
        let completedChat = model.conversations.first { $0.id == photoChat.conversationID }
        XCTAssertEqual(completedChat?.messages.last?.activity?.state, .completed)
        XCTAssertFalse(model.computerWork.isComputerWorkActive)
        XCTAssertNil(model.computerWork.pendingAgentGoal)
        XCTAssertEqual(model.foregroundRun.response(in: work.conversationID), work)
        let chatRequests = await test.provider.chatRequests
        XCTAssertEqual(chatRequests, 0)
    }

    func testRemoteChatLaunchesClosedSystemPhotosWithoutReview() async throws {
        let test = try configuredHarness()
        defer { test.cleanUp() }
        let model = test.model
        test.select(test.profile(endpoint: "https://models.example.com/v1"), provider: test.provider)
        model.skillContextLoader = { _ in .empty }
        let controller = VyronMacWorkTestController()
        let id = "com.apple.Photos"
        let url = URL(fileURLWithPath: "/System/Applications/Photos.app")
        controller.catalog = [DesktopApplication(installedAt: url, name: "Photos", bundleIdentifier: id)]
        controller.running = []
        model.computerWork.macWorkController = controller

        model.composer.draft = "open photos app"
        XCTAssertTrue(model.canSend)
        model.send()
        try await test.waitUntil { model.mcpConnections.pendingReview != nil || !model.foregroundRun.isGenerating }

        XCTAssertNil(model.mcpConnections.pendingReview)
        XCTAssertEqual(controller.launchedIDs, [id])
        XCTAssertEqual(model.messages.last?.activity?.state, .completed)
        let chatRequests = await test.provider.chatRequests
        XCTAssertEqual(chatRequests, 0)
    }

    func testUnfamiliarAppLaunchReviewBelongsToItsChatWhileWorkContinuesInBackground() async throws {
        let test = try configuredHarness()
        defer { test.cleanUp() }
        let model = test.model
        test.select(test.profile(endpoint: "https://models.example.com/v1"), provider: test.provider)
        model.skillContextLoader = { _ in .empty }
        let controller = VyronMacWorkTestController()
        let id = "com.spotify.client"
        let url = URL(fileURLWithPath: "/Applications/Spotify.app")
        controller.catalog = [DesktopApplication(installedAt: url, name: "Spotify", bundleIdentifier: id)]
        controller.running = []
        model.computerWork.macWorkController = controller

        let pendingWork = AsyncStream<Void>.makeStream()
        defer {
            model.mcpConnections.respondToReview(false)
            pendingWork.continuation.finish()
            _ = model.foregroundRun.shutdown()
        }
        let work = startBackgroundWork(in: model, waitingOn: pendingWork.stream)

        model.composer.draft = "open spotify app"
        XCTAssertTrue(model.canSend)
        model.send()
        try await test.waitUntil { model.mcpConnections.pendingReview != nil || !model.foregroundRun.isGenerating }

        let review = try XCTUnwrap(model.mcpConnections.pendingReview, model.messages.last?.content ?? "")
        let appChat = try XCTUnwrap(model.foregroundRun.activeResponse)
        let owner = VyronNotificationResponseID(conversationID: appChat.conversationID, responseID: appChat.messageID)
        let details = try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: Data(review.arguments.utf8))
        XCTAssertEqual(details["application_path"], .string(url.path))
        XCTAssertEqual(model.notifications.reviewObservation?.requestID, review.id)
        XCTAssertEqual(model.notifications.reviewObservation?.target, .response(owner))
        XCTAssertTrue(model.canPresentMCPReview)
        XCTAssertTrue(controller.launchedIDs.isEmpty)
        XCTAssertEqual(model.foregroundRun.response(in: work.conversationID), work)

        model.mcpConnections.respondToReview(true)
        try await test.waitUntil { !model.foregroundRun.isGenerating }

        XCTAssertEqual(controller.launchedIDs, [id])
        XCTAssertEqual(model.messages.last?.activity?.state, .completed)
        XCTAssertEqual(model.foregroundRun.response(in: work.conversationID), work)
        let chatRequests = await test.provider.chatRequests
        XCTAssertEqual(chatRequests, 0)
    }

    func testRemoteModelDoesNotTransferAComputerTaskOrCallItsProvider() async throws {
        let test = try configuredHarness()
        defer { test.cleanUp() }
        let profile = test.profile(endpoint: "https://models.example.com/v1")
        test.select(profile, provider: test.provider)
        test.model.composer.draft = "Click the Safari address bar"
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

    private func startBackgroundWork(in model: AppModel, waitingOn stream: AsyncStream<Void>) -> VyronResponseIdentity {
        var conversation = Conversation(title: "Background Work", workspacePath: nil)
        conversation.mode = ComposerMode.agent.rawValue
        let message = ChatMessage(role: .assistant, content: "", activity: ResponseActivity())
        conversation.messages = [message]
        model.conversations.append(conversation)
        let work = VyronResponseIdentity(
            generationID: UUID(), conversationID: conversation.id, messageID: message.id
        )
        let steering = VyronForegroundSteering(inbox: VyronSteeringInbox(), skills: VyronSkillResourceTools(commands: []))
        model.foregroundRun.begin(work)
        model.foregroundRun.start(work, route: .steerableDevelopment(steering)) {
            for await _ in stream {}
        }
        model.foregroundRun.beginDevelopment(work)
        XCTAssertTrue(model.foregroundRun.moveResponseToBackground())
        return work
    }

    private func transferGoal(_ test: VyronFeatureTestHarness) async throws -> PendingAgentGoal {
        test.model.composer.draft = "Open Safari"
        XCTAssertTrue(test.model.canSend)
        test.model.send()
        try await test.waitUntil { test.model.computerWork.pendingAgentGoal != nil }
        return try XCTUnwrap(test.model.computerWork.pendingAgentGoal)
    }
}
