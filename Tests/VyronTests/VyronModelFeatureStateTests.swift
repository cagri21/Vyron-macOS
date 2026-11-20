import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronModelFeatureStateTests: XCTestCase {
    func testChatOnlyModelBlocksAgentAndProjectPlanBeforeAnyDevelopmentRequest() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let profile = chatOnlyProfile()
        test.select(profile, provider: test.provider, capabilities: ["tools"])
        await test.model.loadWorkspace(test.project)
        test.model.composer.draft = "Inspect this project"

        for mode in [ComposerMode.agent, .plan] {
            test.model.composer.mode = mode
            XCTAssertFalse(test.model.isComposerModeAvailable(mode))
            XCTAssertFalse(test.model.canSend)
            test.model.send()
        }

        test.model.requestModelFeatureVerification()
        XCTAssertFalse(test.model.modelFeatures.isVerifying)
        XCTAssertTrue(test.model.messages.isEmpty)
        XCTAssertEqual(test.model.composer.draft, "Inspect this project")
        let verifications = await test.provider.verificationRequests
        let development = await test.provider.developmentRequests
        XCTAssertEqual(verifications, 0)
        XCTAssertEqual(development, 0)
    }

    func testChatOnlyModelStillCompletesChat() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.select(
            chatOnlyProfile(),
            provider: test.provider
        )
        test.model.composer.mode = .chat
        test.model.composer.draft = "Explain this concept"
        XCTAssertTrue(test.model.canSend)
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertEqual(test.model.messages.last?.content, "Feature test answer")
        XCTAssertNil(test.model.errorMessage)
        let chat = await test.provider.chatRequests
        let development = await test.provider.developmentRequests
        XCTAssertEqual(chat, 1)
        XCTAssertEqual(development, 0)
    }

    func testStandalonePlanKeepsPlainChatTransportWithoutTools() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.select(
            chatOnlyProfile(),
            provider: test.provider
        )
        test.model.composer.mode = .plan
        test.model.composer.draft = "Plan a small application"
        XCTAssertTrue(test.model.isComposerModeAvailable(.plan))
        XCTAssertTrue(test.model.canSend)
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertEqual(test.model.messages.last?.content, "Feature test answer")
        let chat = await test.provider.chatRequests
        let development = await test.provider.developmentRequests
        XCTAssertEqual(chat, 1)
        XCTAssertEqual(development, 0)
    }

    func testSelectingCapableLocalModelReenablesProjectModesWithoutRestart() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let profile = ModelConnectionProfile(
            name: "Local test server", kind: .ollama, endpoint: "http://localhost:11434", selectedModel: "qwen3:4b"
        )
        test.select(profile, provider: test.provider, capabilities: ["tools"])
        await test.model.loadWorkspace(test.project)
        test.model.composer.mode = .agent
        test.model.composer.draft = "Inspect this project"
        XCTAssertFalse(test.model.canSend)

        test.model.modelSelection.models.append(LocalModel(name: "custom-coder:q4", size: 1, capabilities: ["tools"]))
        test.model.useLocalModel("custom-coder:q4")

        XCTAssertEqual(test.model.modelSelection.selectedModel, "custom-coder:q4")
        XCTAssertEqual(test.model.modelFeatureReport[.agent].status, .available)
        XCTAssertTrue(test.model.isComposerModeAvailable(.agent))
        XCTAssertTrue(test.model.isComposerModeAvailable(.plan))
        XCTAssertTrue(test.model.canSend)
        let verifications = await test.provider.verificationRequests
        XCTAssertEqual(verifications, 0, "Advertised native tools should not launch an unnecessary probe.")
    }

    func testStaleProbeCannotApplyToAnotherConnectionWithSameModelID() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let oldProvider = VyronFeatureTestProvider()
        await oldProvider.holdVerification()
        defer { Task { await oldProvider.releaseVerification() } }
        let oldProfile = test.profile()
        test.select(oldProfile, provider: oldProvider)
        test.model.requestModelFeatureVerification()
        let oldTask = test.model.modelFeatures.verificationTask
        try await test.waitUntil { await oldProvider.verificationRequests == 1 }

        let nextProfile = test.profile(endpoint: "http://localhost:5678/v1")
        test.select(nextProfile, provider: test.provider)
        test.model.requestModelFeatureVerification()
        let nextTask = test.model.modelFeatures.verificationTask
        await nextTask?.value
        await oldProvider.releaseVerification()
        await oldTask?.value

        XCTAssertEqual(test.model.modelFeatureReport[.agent].status, .available)
        XCTAssertEqual(test.model.modelFeatures.toolChecks.count, 1)
        XCTAssertEqual(test.model.modelFeatures.toolChecks.first?.selection.connection?.id, nextProfile.id)
        XCTAssertFalse(test.model.modelFeatures.isVerifying)
    }

    func testTransientVerificationFailureRemainsRetryableAndChatAvailable() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        await test.provider.failVerification(with: .connectionFailed)
        test.select(test.profile(), provider: test.provider)
        test.model.requestModelFeatureVerification()
        await test.model.modelFeatures.verificationTask?.value

        XCTAssertEqual(test.model.modelFeatureReport[.agent].status, .unverified)
        XCTAssertEqual(test.model.modelFeatureReport[.agent].reason, .nativeToolVerificationFailed)
        test.model.composer.draft = "Chat is still usable"
        XCTAssertTrue(test.model.canSend)

        await test.provider.failVerification(with: nil)
        test.model.retryModelFeatureVerification()
        await test.model.modelFeatures.verificationTask?.value

        XCTAssertEqual(test.model.modelFeatureReport[.agent].status, .available)
        let verifications = await test.provider.verificationRequests
        XCTAssertEqual(verifications, 2)
        XCTAssertEqual(test.model.modelFeatures.toolChecks.count, 1)
        XCTAssertFalse(test.model.modelFeatures.isVerifying)
    }

    func testCancelledProbeCannotClearReplacementRetryForTheSameSelection() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        await test.provider.holdVerification()
        defer { Task { await test.provider.releaseVerification() } }
        test.select(test.profile(), provider: test.provider)
        test.model.requestModelFeatureVerification()
        let oldTask = test.model.modelFeatures.verificationTask
        try await test.waitUntil { await test.provider.verificationRequests == 1 }

        test.model.retryModelFeatureVerification()
        let replacementTask = test.model.modelFeatures.verificationTask
        try await test.waitUntil { await test.provider.verificationRequests == 2 }
        await test.provider.releaseVerification(1)
        await oldTask?.value

        XCTAssertTrue(test.model.modelFeatures.isVerifying)
        XCTAssertNotNil(test.model.modelFeatures.verificationTask)
        XCTAssertTrue(test.model.modelFeatures.toolChecks.isEmpty)

        await test.provider.releaseVerification(2)
        await replacementTask?.value
        XCTAssertEqual(test.model.modelFeatureReport[.agent].status, .available)
        XCTAssertEqual(test.model.modelFeatures.toolChecks.count, 1)
        XCTAssertFalse(test.model.modelFeatures.isVerifying)
        XCTAssertNil(test.model.modelFeatures.verificationTask)
    }

    func testRestoringChatOnlyAgentConversationPreservesHistoryAndQueuedMessages() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.select(
            chatOnlyProfile(),
            provider: test.provider
        )
        await test.model.loadWorkspace(test.project)
        var conversation = Conversation(title: "Existing Agent chat", workspacePath: test.project.path)
        conversation.mode = ComposerMode.agent.rawValue
        conversation.messages = [ChatMessage(role: "user", content: "Keep this history")]
        conversation.queuedMessages = [VyronQueuedMessage(content: "Keep this queued message")]
        test.model.conversations = [conversation]
        test.model.selectedConversationID = nil
        test.model.selectConversation(conversation.id)
        test.model.composer.draft = "A follow-up"

        XCTAssertEqual(test.model.composer.mode, .agent)
        XCTAssertFalse(test.model.canSend)
        test.model.send()
        XCTAssertEqual(test.model.messages.map(\.content), ["Keep this history"])
        XCTAssertEqual(test.model.queuedMessages.map(\.content), ["Keep this queued message"])
        XCTAssertEqual(test.model.selectedConversation?.mode, ComposerMode.agent.rawValue)
        XCTAssertEqual(test.model.composer.draft, "A follow-up")
        let development = await test.provider.developmentRequests
        XCTAssertEqual(development, 0)
    }

    func testScheduledAutomaticSelectionDefersHelperEligibilityToRuntimeRouter() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let automatic = VyronScheduledModelSelection(
            connectionID: nil, model: "qwen3:4b", automaticallySelect: true, effort: .balanced
        )
        let manual = VyronScheduledModelSelection(
            connectionID: nil, model: "qwen3:4b", automaticallySelect: false, effort: .balanced
        )

        let automaticReport = test.model.scheduledModelFeatureReport(automatic)
        XCTAssertEqual(automaticReport[.agent].status, .unverified)
        XCTAssertTrue(automaticReport[.agent].isEnabled)
        XCTAssertTrue(automaticReport[.plan].isEnabled)

        let manualReport = test.model.scheduledModelFeatureReport(manual)
        XCTAssertEqual(manualReport[.agent].status, .unavailable)
        XCTAssertEqual(manualReport[.agent].reason, .helperModelReservedForChat)
        XCTAssertFalse(manualReport[.plan].isEnabled)
    }

    private func chatOnlyProfile() -> ModelConnectionProfile {
        ModelConnectionProfile(
            name: "Chat-only local helper",
            kind: .ollama,
            endpoint: "http://localhost:11434",
            selectedModel: "qwen3:4b"
        )
    }
}
