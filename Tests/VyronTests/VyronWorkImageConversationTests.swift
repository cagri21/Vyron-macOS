import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronWorkImageConversationTests: XCTestCase {
    func testExistingWorkConversationImportsImagesWithoutChangingMode() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronWorkImageTestProvider()
        try await prepareWork(test, provider: provider)
        var conversation = Conversation(title: "Existing work", workspacePath: test.project.path)
        conversation.mode = ComposerMode.agent.rawValue
        conversation.messages = [ChatMessage(role: "user", content: "Explain the project.")]
        test.model.conversations = [conversation]
        test.model.selectedConversationID = conversation.id
        test.model.composer.draft = "Explain this screenshot."

        XCTAssertTrue(test.model.canAttachScreenshots)
        test.model.attachCapturedScreenshot(try VyronScreenshotTestImage.jpeg(), name: "Work screen.jpg")
        XCTAssertTrue(test.model.composerAttachments.screenshotDraft.isLoading)
        XCTAssertFalse(test.model.canSend)
        try await test.waitUntil { !test.model.composerAttachments.screenshotDraft.isLoading }

        XCTAssertEqual(test.model.composer.mode, .agent)
        XCTAssertEqual(test.model.composerAttachments.screenshotDraft.images.count, 1)
        XCTAssertEqual(test.model.composerAttachments.screenshotDraft.images.first?.name, "Work screen.jpg")
        XCTAssertEqual(test.model.composer.draft, "Explain this screenshot.")
        XCTAssertTrue(test.model.canSend)
        XCTAssertNil(test.model.errorMessage)
    }

    func testWorkImageSendReachesDevelopmentAndPersistsForTextFollowUp() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronWorkImageTestProvider()
        try await prepareWork(test, provider: provider)
        let image = try VyronScreenshotTestImage.attachment(name: "Reference.jpg")
        test.model.composerAttachments.screenshotDraft.images = [image]
        test.model.composer.draft = "Explain the visible interface without editing project files."

        XCTAssertTrue(test.model.canSend)
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        var requests = await provider.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(try XCTUnwrap(requests.first).flatMap { $0.images ?? [] }, [image])
        XCTAssertTrue(test.model.composerAttachments.screenshotDraft.images.isEmpty)
        XCTAssertEqual(test.model.composer.mode, .agent)
        XCTAssertNil(test.model.errorMessage)
        let stored = try Data(contentsOf: test.directory.appendingPathComponent("conversations.json"))
        let restored = try JSONDecoder().decode([Conversation].self, from: stored)
        XCTAssertEqual(restored.first?.messages.first?.images, [image])
        XCTAssertEqual(restored.first?.mode, ComposerMode.agent.rawValue)

        test.model.composer.draft = "Explain the same screenshot in more detail without editing files."
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        requests = await provider.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(try XCTUnwrap(requests.last).flatMap { $0.images ?? [] }, [image])
        XCTAssertNil(test.model.messages.last(where: { $0.role == "user" })?.images)
        XCTAssertNil(test.model.errorMessage)
        let chats = await provider.chatRequests
        XCTAssertEqual(chats, 0)
    }

    func testPlanAcceptsImagesAndKeepsReadOnlyDevelopmentMode() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronWorkImageTestProvider()
        try await prepareWork(test, provider: provider)
        test.model.composer.mode = .plan
        test.model.attachCapturedScreenshot(try VyronScreenshotTestImage.jpeg(), name: "Plan screen.jpg")
        try await test.waitUntil { !test.model.composerAttachments.screenshotDraft.isLoading }
        let image = try XCTUnwrap(test.model.composerAttachments.screenshotDraft.images.first)
        test.model.composer.draft = "Explain a plan for this interface without making changes."

        XCTAssertEqual(test.model.composer.mode, .plan)
        XCTAssertTrue(test.model.canSend)
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let requests = await provider.requests
        let modes = await provider.requestedModes
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(try XCTUnwrap(requests.first).flatMap { $0.images ?? [] }, [image])
        XCTAssertEqual(modes, [.plan])
        XCTAssertEqual(test.model.composer.mode, .plan)
        XCTAssertNil(test.model.errorMessage)
    }

    func testWorkImagesKeepSelectedModelAndBypassComputerRoutingWhenAutoIsEnabled() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronWorkImageTestProvider()
        try await prepareWork(test, provider: provider)
        test.model.modelSelection.activeConnectionID = nil
        test.model.modelSelection.models = [
            LocalModel(name: "image-test", size: 1, capabilities: ["vision", "tools"]),
            LocalModel(name: "qwen3-coder:30b", size: 18_000_000_000, capabilities: ["tools"])
        ]
        test.model.modelSelection.selectedModel = "image-test"
        test.model.modelSelection.automaticModelSelection = true
        test.model.computerWork.automaticRequestRouting = true
        test.model.composerAttachments.screenshotDraft.images = [try VyronScreenshotTestImage.attachment()]
        test.model.composer.draft = "Open Safari and search for pharmacies in Istanbul. Explain the screenshot only."

        XCTAssertTrue(test.model.canSend)
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let models = await provider.requestedModels
        let automatic = await provider.automaticSelections
        XCTAssertEqual(models, ["image-test"])
        XCTAssertFalse(automatic.contains(true))
        XCTAssertFalse(test.model.computerWork.isComputerWorkActive)
        XCTAssertNil(test.model.computerWork.pendingAgentGoal)
        XCTAssertFalse(test.model.appNavigation.showAutomation)
        XCTAssertNil(test.model.errorMessage)
    }

    private func prepareWork(
        _ test: VyronFeatureTestHarness,
        provider: VyronWorkImageTestProvider
    ) async throws {
        test.select(test.profile(modelName: "image-test"), provider: provider, capabilities: ["vision", "tools"])
        test.model.skillContextLoader = { _ in .empty }
        test.model.computerWork.automaticRequestRouting = false
        await test.model.loadWorkspace(test.project)
        test.model.composer.mode = .agent
        XCTAssertFalse(test.model.workspaceState.isLoadingWorkspace)
        XCTAssertNil(test.model.errorMessage)
    }
}
