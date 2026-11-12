import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronMacWorkIntegrationTests: XCTestCase {
    func testRemoteWorkCapturesWindowAndReturnsPixelsToSameModelWithPersistedArtifact() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronMacWorkIntegrationProvider()
        let capture = VyronMacWorkIntegrationCapture(data: try VyronScreenshotTestImage.jpeg())
        try await configure(test, provider: provider, capture: capture)
        let connectionID = test.model.modelSelection.activeConnectionID
        let modelName = test.model.modelSelection.selectedModel
        test.model.composer.draft = "Check the app window and take a screenshot."
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let requests = await provider.requests
        XCTAssertEqual(requests.count, 3)
        let finalRequest = try XCTUnwrap(requests.last)
        let windowsReply = try XCTUnwrap(finalRequest.firstIndex {
            $0.role == "tool" && $0.toolCallID == VyronMacWorkIntegrationProvider.windowsCallID
        })
        let captureReply = try XCTUnwrap(finalRequest.firstIndex {
            $0.role == "tool" && $0.toolCallID == VyronMacWorkIntegrationProvider.screenshotCallID
        })
        let observation = try XCTUnwrap(finalRequest.firstIndex { !($0.images ?? []).isEmpty })
        XCTAssertLessThan(windowsReply, captureReply)
        XCTAssertLessThan(captureReply, observation)
        XCTAssertEqual(finalRequest[observation].role, "user")
        let image = try XCTUnwrap(finalRequest[observation].images?.first)
        XCTAssertEqual(image.mimeType, "image/png")
        XCTAssertTrue(image.data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(finalRequest.filter { $0.role == "tool" }.flatMap { $0.images ?? [] }, [])

        XCTAssertEqual(test.model.messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(test.model.messages.last?.capturedImages, [image])
        XCTAssertNil(test.model.messages.last?.images)
        XCTAssertFalse(test.model.computerWork.isComputerWorkActive)
        XCTAssertNil(test.model.computerWork.pendingAgentGoal)
        XCTAssertEqual(test.model.modelSelection.activeConnectionID, connectionID)
        XCTAssertEqual(test.model.modelSelection.selectedModel, modelName)
        let selectedModels = await provider.requestedModels
        let automaticSelections = await provider.automaticSelections
        let chatRequests = await provider.chatRequests
        XCTAssertEqual(selectedModels, Array(repeating: modelName, count: 3))
        XCTAssertEqual(automaticSelections, [false])
        XCTAssertEqual(chatRequests, 0)
        XCTAssertEqual(capture.captureRequests, 1)
        XCTAssertEqual(capture.permissionRequests, 0)
        let catalogs = await provider.toolCatalogs
        XCTAssertTrue(catalogs.allSatisfy { $0.contains { $0.name == "vyron_mac_screenshot" } })

        let stored = try restoredConversations(test)
        let conversationID = try XCTUnwrap(test.model.selectedConversationID)
        let conversation = try XCTUnwrap(stored.first { $0.id == conversationID })
        XCTAssertEqual(conversation.messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(conversation.messages.last?.capturedImages, [image])
    }

    func testStoppingAndChangingChatDiscardsLateCaptureWithoutFurtherInference() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = VyronMacWorkIntegrationProvider()
        let capture = VyronMacWorkIntegrationCapture(data: try VyronScreenshotTestImage.jpeg())
        capture.holdsCapture = true
        try await configure(test, provider: provider, capture: capture)
        test.model.composer.draft = "Take a screenshot of the app."
        test.model.send()
        try await test.waitUntil { capture.captureRequests == 1 }
        let sourceID = try XCTUnwrap(test.model.selectedConversationID)
        test.model.stopGeneration()
        test.model.newConversation()
        capture.releaseCaptures()
        try await test.waitUntil { capture.finishedCaptures == 1 && !test.model.foregroundRun.isStoppingDevelopment }

        let requests = await provider.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(test.model.messages.isEmpty)
        let source = try XCTUnwrap(test.model.conversations.first { $0.id == sourceID })
        XCTAssertTrue(source.messages.allSatisfy { ($0.capturedImages ?? []).isEmpty })
        let stored = try restoredConversations(test)
        let restored = try XCTUnwrap(stored.first { $0.id == sourceID })
        XCTAssertTrue(restored.messages.allSatisfy { ($0.capturedImages ?? []).isEmpty })
    }

    func testScheduledFlagRefusesAnAlreadyCreatedMacRunBeforeNativeRead() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let capture = VyronMacWorkIntegrationCapture(data: try VyronScreenshotTestImage.jpeg())
        test.model.computerWork.macWorkScreenshotCapture = capture
        test.model.computerWork.macWorkController = VyronMacWorkIntegrationController()
        let conversation = Conversation(title: "Work screenshot ownership", workspacePath: test.project.path)
        test.model.conversations = [conversation]
        test.model.selectedConversationID = conversation.id
        let messageID = UUID()
        let response = VyronResponseIdentity(
            generationID: UUID(), conversationID: conversation.id, messageID: messageID
        )
        test.model.foregroundRun.begin(response)
        let run = test.model.makeMacWorkRun(
            context: VyronMacWorkContext(goal: "Take a screenshot", projectRoot: test.project, allowsActions: true),
            response: response
        )
        test.model.isRunningScheduledTask = true
        defer { test.model.isRunningScheduledTask = false }
        do {
            _ = try await run.execute(DevelopmentToolCall(
                name: "vyron_mac_windows",
                arguments: ["application_id": .string(VyronMacWorkIntegrationProvider.applicationID)]
            ))
            XCTFail("Scheduled work must not access interactive Mac screenshot tools.")
        } catch is CancellationError {}
        XCTAssertEqual(capture.sourceRequests, 0)
        XCTAssertEqual(capture.captureRequests, 0)
    }

    private func configure(
        _ test: VyronFeatureTestHarness,
        provider: VyronMacWorkIntegrationProvider,
        capture: VyronMacWorkIntegrationCapture
    ) async throws {
        test.select(
            test.profile(modelName: "remote-vision-tools", endpoint: "https://models.example.com/v1"),
            provider: provider, capabilities: ["vision", "tools"]
        )
        test.model.skillContextLoader = { _ in .empty }
        test.model.computerWork.automaticRequestRouting = true
        test.model.computerWork.macWorkController = VyronMacWorkIntegrationController()
        test.model.computerWork.macWorkScreenshotCapture = capture
        await test.model.loadWorkspace(test.project)
        test.model.composer.mode = .agent
        XCTAssertNil(test.model.errorMessage)
    }

    private func restoredConversations(_ test: VyronFeatureTestHarness) throws -> [Conversation] {
        try JSONDecoder().decode(
            [Conversation].self,
            from: Data(contentsOf: test.directory.appendingPathComponent("conversations.json"))
        )
    }
}
