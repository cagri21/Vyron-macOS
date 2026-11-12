import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronScreenshotConversationTests: XCTestCase {
    func testImageOnlySendReachesModelOnceAndPersistsForFollowUp() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronScreenshotTestProvider()
        test.select(test.profile(), provider: provider, capabilities: ["vision"])
        let data = try VyronScreenshotTestImage.jpeg()
        test.model.attachCapturedScreenshot(data, name: "Simulator.jpg")
        XCTAssertTrue(test.model.composerAttachments.screenshotDraft.isLoading)
        XCTAssertFalse(test.model.canSend)
        try await test.waitUntil { !test.model.composerAttachments.screenshotDraft.isLoading }
        let image = try XCTUnwrap(test.model.composerAttachments.screenshotDraft.images.first)
        XCTAssertEqual(test.model.composer.mode, .chat)
        XCTAssertTrue(test.model.canSend)

        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertTrue(test.model.composerAttachments.screenshotDraft.images.isEmpty)
        var requests = await provider.receivedMessages
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].flatMap { $0.images ?? [] }, [image])
        XCTAssertNil(test.model.errorMessage)

        let stored = try Data(contentsOf: test.directory.appendingPathComponent("conversations.json"))
        let restored = try JSONDecoder().decode([Conversation].self, from: stored)
        XCTAssertEqual(restored.first?.messages.first?.images, [image])

        test.model.composer.draft = "Explain the same screen in more detail."
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        requests = await provider.receivedMessages
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].flatMap { $0.images ?? [] }, [image])
        XCTAssertNil(test.model.messages.last?.images)
    }

    func testScreenshotChatBypassesComputerAndWebRoutingAndKeepsSelectedModelWithAuto() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronScreenshotTestProvider()
        test.model.modelSelection.isConnected = false
        test.model.modelSelection.activeConnectionID = nil
        test.model.modelSelection.configuredInferenceClient = provider
        test.model.modelSelection.models = [
            LocalModel(name: "image-test", size: 1, capabilities: ["vision"]),
            LocalModel(name: "qwen3-coder:30b", size: 18_000_000_000, capabilities: ["tools"])
        ]
        test.model.modelSelection.selectedModel = "image-test"
        test.model.modelSelection.automaticModelSelection = true
        test.model.modelSelection.isConnected = true
        test.model.computerWork.automaticRequestRouting = true
        test.model.composerAttachments.screenshotDraft.images = [try VyronScreenshotTestImage.attachment()]
        test.model.composer.draft = "Open Safari and search for pharmacies in Istanbul. Explain the screen only."

        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let models = await provider.receivedModels
        let requests = await provider.receivedMessages
        let development = await provider.developmentRequests
        XCTAssertEqual(models, ["image-test"])
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(development, 0)
        XCTAssertFalse(test.model.computerWork.isComputerWorkActive)
        XCTAssertNil(test.model.computerWork.pendingAgentGoal)
        XCTAssertFalse(test.model.appNavigation.showAutomation)
        XCTAssertNil(test.model.errorMessage)
    }

    func testImagesCannotBeLostIntoTextOnlyQueue() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.select(test.profile(), provider: test.provider, capabilities: ["vision", "tools"])
        let image = try VyronScreenshotTestImage.attachment()
        test.model.composerAttachments.screenshotDraft.images = [image]
        test.model.composer.draft = "Analyze this screen."
        let response = test.model.beginTestForegroundResponse()
        XCTAssertFalse(test.model.canSend)
        XCTAssertFalse(test.model.canAttachScreenshots)
        test.model.send()
        test.model.attachCapturedScreenshot(image.data, name: "New.jpg")
        XCTAssertEqual(test.model.composerAttachments.screenshotDraft.images, [image])
        XCTAssertEqual(test.model.composer.draft, "Analyze this screen.")
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
        test.model.foregroundRun.complete(response.generationID)
    }

    func testBoundedHistoryPreservesImageAndProjectContextAndKeepsNewestImageTurns() throws {
        let images = try (0..<5).map { try VyronScreenshotTestImage.attachment(name: "Screen \($0).jpg") }
        let messages = images.enumerated().map { index, image in
            ChatMessage(role: "user", content: "Screen \(index)", images: [image])
        }
        let latest = try XCTUnwrap(messages.last)
        let bounded = VyronConversationRequestContext.boundedHistory(
            messages, context: [latest.id.uuidString: "Project file list"]
        )

        XCTAssertTrue(bounded.omittedOlderMessages)
        XCTAssertEqual(bounded.messages.map(\.id), messages.suffix(4).map(\.id))
        XCTAssertEqual(bounded.messages.flatMap { $0.images ?? [] }, Array(images.suffix(4)))
        XCTAssertTrue(bounded.messages.last?.content.contains("Project file list") == true)
        XCTAssertEqual(bounded.messages.last?.images, [try XCTUnwrap(images.last)])
    }
}
