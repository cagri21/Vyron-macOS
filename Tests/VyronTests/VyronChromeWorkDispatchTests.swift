import Foundation
import XCTest
import VyronAutomation
import VyronCore
@testable import Vyron

@MainActor
final class VyronChromeWorkDispatchTests: XCTestCase {
    func testWorkDispatchesChromeToolAndPlanOmitsMutationTool() async throws {
        for mode in [ComposerMode.agent, .plan] {
            let test = VyronQueueTestHarness()
            defer { test.cleanUp() }
            let project = test.directory.appendingPathComponent("Project")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            try Data("Project notes".utf8).write(to: project.appendingPathComponent("README.md"))
            await test.model.loadWorkspace(project)
            var conversation = Conversation(title: "Chrome Work", workspacePath: project.path)
            conversation.projectPath = test.model.sidebarActiveProjectPath
            conversation.mode = ComposerMode.agent.rawValue
            test.model.conversations = [conversation]
            test.model.selectedConversationID = conversation.id
            test.model.composer.mode = mode
            test.model.computerWork.automaticRequestRouting = true
            test.model.chromeBridge = VyronChromeBridgeClient(root: test.directory.appendingPathComponent("chrome"))
            test.send("Inspect my connected Chrome tab with the Chrome extension.")
            try await waitUntil { await test.provider.developmentRequests.count == 1 }
            XCTAssertFalse(test.model.appNavigation.showAutomation)
            let catalogs = await test.provider.developmentToolCatalogs
            XCTAssertTrue(catalogs[0].contains { $0.name == VyronChromeTools.sessions })
            XCTAssertEqual(catalogs[0].contains { $0.name == VyronChromeTools.action }, mode == .agent)
            await test.provider.completeDevelopment(0, message: DevelopmentMessage(
                role: "assistant", toolCalls: [DevelopmentToolCall(name: VyronChromeTools.sessions, arguments: [:])]
            ))
            try await waitUntil { await test.provider.developmentRequests.count == 2 }
            let requests = await test.provider.developmentRequests
            XCTAssertTrue(requests[1].contains { $0.role == "tool" && $0.content.contains("[]") })
            await test.provider.completeDevelopment(1, message: DevelopmentMessage(
                role: "assistant", content: "No tabs are connected. Connect one in the Chrome extension."
            ))
            try await waitUntil { !test.model.foregroundRun.isGenerating }
            XCTAssertFalse(test.model.computerWork.isComputerWorkActive)
        }
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The Chrome tool dispatch did not reach its expected state.")
        throw CancellationError()
    }
}
