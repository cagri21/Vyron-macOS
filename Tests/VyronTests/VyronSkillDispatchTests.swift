import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronSkillDispatchTests: XCTestCase {
    func testChatLoadsRealSelectedSkillWithoutChangingUserMessage() async throws {
        let test = try VyronSideChatTestHarness()
        addTeardownBlock { await test.cleanUp() }
        let root = VyronSkillRoot(directoryURL: test.directory, source: .codex, scope: .personal)
        let directory = test.directory.appendingPathComponent("example")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let instructions = "---\nname: example\ndescription: A test skill\n---\n\nAlways explain with a tiny example."
        try instructions.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        test.model.skillContextLoader = { request in
            try await VyronSkillContextLoader.load(VyronSkillContextRequest(prompt: request.prompt, roots: [root]))
        }
        test.model.computerWork.automaticRequestRouting = true
        test.model.composer.draft = "/example Explain how this works."
        test.model.send()
        try await test.waitUntil { await test.provider.requests.count == 1 }
        let captured = await test.provider.requests
        let request = try XCTUnwrap(captured.first)
        XCTAssertTrue(request.messages.last?.content.hasPrefix("/example Explain how this works.") == true)
        XCTAssertTrue(request.messages.last?.content.contains(instructions) == true)
        XCTAssertTrue(request.messages.last?.content.contains(directory.path) == true)
        let user = try XCTUnwrap(test.model.messages.last { $0.role == "user" })
        XCTAssertEqual(user.content, "/example Explain how this works.")
        XCTAssertTrue(test.model.selectedConversation?.contextByMessageID?[user.id.uuidString]?.contains(instructions) == true)
        await test.provider.complete(1, answer: "A tiny example.")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
    }

    func testLateSkillLoadCannotDispatchStoppedOrNewerRequest() async throws {
        let test = try VyronSideChatTestHarness()
        let loader = VyronSkillContextTestLoader()
        addTeardownBlock { await test.cleanUp() }
        test.model.skillContextLoader = { try await loader.load($0) }
        test.model.composer.draft = "/old First task"
        test.model.send()
        try await test.waitUntil { await loader.requests.count == 1 }
        test.model.stopGeneration()
        test.model.composer.draft = "/new Second task"
        test.model.send()
        try await test.waitUntil { await loader.requests.count == 2 }
        await loader.complete(1, text: "STALE_SKILL_INSTRUCTIONS")
        await loader.complete(2, text: "CURRENT_SKILL_INSTRUCTIONS")
        try await test.waitUntil { await test.provider.requests.count == 1 }
        let requests = await test.provider.requests
        XCTAssertTrue(requests[0].messages.last?.content.contains("CURRENT_SKILL_INSTRUCTIONS") == true)
        XCTAssertFalse(requests[0].messages.contains { $0.content.contains("STALE_SKILL_INSTRUCTIONS") })
        await test.provider.complete(1, answer: "Current answer")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
    }

    func testFailedSkillReadStopsBeforeInferenceAndRetainsUserRequest() async throws {
        let test = try VyronSideChatTestHarness()
        addTeardownBlock { await test.cleanUp() }
        test.model.skillContextLoader = { _ in throw CocoaError(.fileReadNoSuchFile) }
        test.model.composer.draft = "/example Keep this task"
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        let requests = await test.provider.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertNotNil(test.model.errorMessage)
        XCTAssertEqual(test.model.messages.last { $0.role == "user" }?.content, "/example Keep this task")
        XCTAssertEqual(test.model.messages.last?.activity?.state, .failed)
    }

    func testOversizedChatSkillFailsRatherThanDroppingInstructions() async throws {
        let test = try VyronSideChatTestHarness()
        addTeardownBlock { await test.cleanUp() }
        test.model.skillContextLoader = { _ in
            VyronSkillRequestContext(text: String(repeating: "x", count: 24_000), commands: [])
        }
        test.model.composer.draft = "/large Explain this"
        test.model.send()
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        let requests = await test.provider.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(test.model.errorMessage, VyronSkillText.contextTooLong)
    }

    func testPlainPromptSkipsLocalDiscovery() async throws {
        let context = try await VyronSkillContextLoader.load(VyronSkillContextRequest(
            prompt: "Explain a normal task.",
            roots: [VyronSkillRoot(directoryURL: URL(fileURLWithPath: "/missing"), source: .codex, scope: .personal)]
        ))
        XCTAssertNil(context.text)
        XCTAssertTrue(context.commands.isEmpty)
    }

    func testMissingSlashCommandFailsInsteadOfSilentlyDroppingSelection() async {
        do {
            _ = try await VyronSkillContextLoader.load(VyronSkillContextRequest(prompt: "/missing Implement this", roots: []))
            XCTFail("A missing selected skill must be reported before inference.")
        } catch VyronSkillContextError.unavailable {
            // The composer can refresh the inventory and select an available command.
        } catch {
            XCTFail("Unexpected skill error: \(error)")
        }
    }
}
