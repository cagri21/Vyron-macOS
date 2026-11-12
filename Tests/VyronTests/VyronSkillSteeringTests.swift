import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronSkillSteeringTests: XCTestCase {
    func testSteeringLoadsAndDeliversSkillsInSubmissionOrder() async throws {
        let test = VyronQueueTestHarness()
        let loader = VyronSkillContextTestLoader()
        defer { test.cleanUp() }
        try await openProject(test)
        test.model.skillContextLoader = { request in
            if request.prompt == "Inspect the project" { return .empty }
            return try await loader.load(request)
        }
        test.send("Inspect the project")
        try await waitUntil { await test.provider.developmentRequests.count == 1 }
        test.send("/first Restrict the scope")
        let first = try XCTUnwrap(test.model.queuedMessages.last?.id)
        test.send("/second Apply the newer correction")
        let second = try XCTUnwrap(test.model.queuedMessages.last?.id)
        test.model.steerQueuedMessage(first)
        test.model.steerQueuedMessage(second)
        try await waitUntil { await loader.requests.count == 1 }
        await loader.complete(1, text: "FIRST_GUIDANCE")
        try await waitUntil { await loader.requests.count == 2 }
        await loader.complete(2, text: "SECOND_GUIDANCE")
        try await waitUntil {
            test.model.selectedConversation?.contextByMessageID?[second.uuidString] == "SECOND_GUIDANCE"
        }
        let updates = await test.model.foregroundRun.activeSteeringInbox?.drain()
        XCTAssertEqual(updates?.map(\.id), [first, second])
        XCTAssertTrue(updates?.first?.content.contains("FIRST_GUIDANCE") == true)
        XCTAssertTrue(updates?.last?.content.contains("SECOND_GUIDANCE") == true)
        test.model.stopGeneration()
        try await waitUntil { !test.model.foregroundRun.isStoppingDevelopment }
        XCTAssertEqual(test.model.queuedMessages.map(\.id), [first, second])
        XCTAssertTrue(test.model.composer.pendingSteeringIDs.isEmpty)
        XCTAssertNil(test.model.foregroundRun.activeSteeringInbox)
    }

    func testSkillSteeredDuringInitialLoadCanReadItsReferences() async throws {
        let test = VyronQueueTestHarness()
        let loader = VyronSkillContextTestLoader()
        defer { test.cleanUp() }
        try await openProject(test)
        let initial = try command("initial", in: test.directory)
        let next = try command("next", in: test.directory)
        let catalog = [initial, next]
        test.model.skillContextLoader = { try await loader.load($0) }
        test.send("/initial Inspect the project")
        try await waitUntil { await loader.requests.count == 1 }
        let tools = try XCTUnwrap(test.model.foregroundRun.activeSkillTools)
        test.send("/next Restrict the scope")
        let steeringID = try XCTUnwrap(test.model.queuedMessages.first?.id)
        test.model.steerQueuedMessage(steeringID)
        try await waitUntil { await loader.requests.count == 2 }
        await loader.resolve(2, context: VyronSkillRequestContext(
            text: "NEXT_GUIDANCE", commands: [next], catalog: catalog
        ))
        try await waitUntil {
            test.model.selectedConversation?.contextByMessageID?[steeringID.uuidString] == "NEXT_GUIDANCE"
        }
        let call = DevelopmentToolCall(
            name: "read_skill_resource", arguments: ["skill": .string(next.name), "path": .string("SKILL.md")]
        )
        let beforeStart = try await tools.execute(call)
        XCTAssertFalse(beforeStart.isError)
        XCTAssertTrue(beforeStart.text.contains("Instructions for next"))
        await loader.resolve(1, context: VyronSkillRequestContext(
            text: "INITIAL_GUIDANCE", commands: [initial], catalog: catalog
        ))
        try await waitUntil { await test.provider.developmentRequests.count == 1 }
        let afterStart = try await tools.execute(call)
        XCTAssertFalse(afterStart.isError)
        let requests = await test.provider.developmentRequests
        XCTAssertTrue(requests[0].contains { $0.content.contains("INITIAL_GUIDANCE") })
        XCTAssertTrue(requests[0].contains { $0.content.contains("NEXT_GUIDANCE") })
        await test.provider.completeDevelopment(0, message: DevelopmentMessage(
            role: "assistant", content: "The project contains a README. No files changed."
        ))
        try await waitUntil { !test.model.foregroundRun.isGenerating }
        XCTAssertEqual(test.model.messages.first { $0.id == steeringID }?.content, "/next Restrict the scope")
        XCTAssertTrue(test.model.queuedMessages.isEmpty)
    }

    private func openProject(_ test: VyronQueueTestHarness) async throws {
        let project = test.directory.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "Small project notes.".write(
            to: project.appendingPathComponent("README.md"), atomically: true, encoding: .utf8
        )
        await test.model.loadWorkspace(project)
        test.model.composer.mode = .agent
    }

    private func command(_ name: String, in directory: URL) throws -> VyronSkillCommand {
        let root = VyronSkillRoot(directoryURL: directory, source: .codex, scope: .personal)
        let skillDirectory = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        let text = "Instructions for \(name)"
        let file = skillDirectory.appendingPathComponent("SKILL.md")
        try text.write(to: file, atomically: true, encoding: .utf8)
        return VyronSkillCommand(name: name, skill: VyronLocalSkill(
            metadata: VyronSkillMetadata(name: name, description: text), root: root, fileURL: file,
            preview: VyronSkillPreview(content: text, isTruncated: false)
        ))
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Skill steering did not reach the expected boundary.")
        throw CancellationError()
    }
}
