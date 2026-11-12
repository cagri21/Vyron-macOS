import Foundation
import XCTest
import VyronCore
import VyronModelDomain
@testable import Vyron

@MainActor
final class VyronDevelopmentTaskAttachmentTests: XCTestCase {
    func testWorkAttachesTasksAboveTheInlineCharacterLimitAndRestoresTheirContent() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = await prepareProject(test, mode: .agent)
        let inline = String(repeating: "界", count: VyronTaskPromptLimits.maximumCharacters)
        let attached = "  " + inline + "!\n"

        test.model.composer.draft = inline
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let inlineMessage = try XCTUnwrap(test.model.messages.first { $0.conversationRole == .user })
        XCTAssertEqual(inlineMessage.content, inline)
        XCTAssertNil(inlineMessage.developmentTaskFilename)

        test.model.composer.draft = attached
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let requests = await provider.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(try XCTUnwrap(requests.last).contains { $0.role == "user" && $0.content.contains(attached) })
        let attachedMessage = try XCTUnwrap(test.model.messages.last { $0.conversationRole == .user })
        XCTAssertEqual(attachedMessage.content, attached)
        XCTAssertEqual(attachedMessage.developmentTaskFilename, "task-description.txt")
        XCTAssertNil(test.model.errorMessage)

        let data = try Data(contentsOf: test.directory.appendingPathComponent("conversations.json"))
        let restored = try JSONDecoder().decode([Conversation].self, from: data)
        XCTAssertEqual(restored.first?.messages.last { $0.conversationRole == .user }, attachedMessage)
    }

    func testPlanAttachesTextThatExceedsTheInlineByteLimitWithFewerCharacters() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = await prepareProject(test, mode: .plan)
        let prompt = String(repeating: "👩🏽‍💻", count: 801)
        XCTAssertLessThan(prompt.count, VyronTaskPromptLimits.maximumCharacters)
        XCTAssertGreaterThan(prompt.utf8.count, VyronTaskPromptLimits.maximumUTF8Bytes)

        test.model.composer.draft = prompt
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let requests = await provider.requests
        let modes = await provider.requestedModes
        XCTAssertEqual(modes, [.plan])
        XCTAssertTrue(try XCTUnwrap(requests.first).contains { $0.role == "user" && $0.content.contains(prompt) })
        let userMessage = try XCTUnwrap(test.model.messages.first { $0.conversationRole == .user })
        XCTAssertEqual(userMessage.content, prompt)
        XCTAssertEqual(userMessage.developmentTaskFilename, "task-description.txt")
        XCTAssertNil(test.model.errorMessage)
    }

    func testProjectGoalAboveTheAttachmentByteLimitPreservesTheDraft() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let provider = await prepareProject(test, mode: .agent)
        let prompt = String(repeating: "x", count: VyronDevelopmentTaskLimits.maximumGoalBytes + 1)

        test.model.composer.draft = prompt
        test.model.send()

        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(test.model.messages.isEmpty)
        XCTAssertEqual(test.model.composer.draft, prompt)
        XCTAssertNotNil(test.model.errorMessage)
    }

    private func prepareProject(_ test: VyronFeatureTestHarness, mode: ComposerMode) async -> VyronWorkImageTestProvider {
        let provider = VyronWorkImageTestProvider()
        test.select(test.profile(), provider: provider, capabilities: ["tools"])
        test.model.skillContextLoader = { _ in .empty }
        test.model.computerWork.automaticRequestRouting = false
        await test.model.loadWorkspace(test.project)
        test.model.composer.mode = mode
        XCTAssertEqual(test.model.composer.mode, mode)
        XCTAssertTrue(test.model.canAcceptConversationMessage)
        return provider
    }
}
