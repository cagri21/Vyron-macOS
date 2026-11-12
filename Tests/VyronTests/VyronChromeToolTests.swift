import Foundation
import XCTest
import VyronAutomation
import VyronCore
@testable import Vyron

@MainActor
final class VyronChromeToolTests: XCTestCase {
    func testSessionsReadDoesNotInitializeOrExposeUnconnectedBrowserData() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let context = startResponse(test)
        let root = test.directory.appendingPathComponent("unused-chrome")
        test.model.chromeBridge = VyronChromeBridgeClient(root: root)
        let result = try await test.model.executeChromeTool(
            DevelopmentToolCall(name: VyronChromeTools.sessions, arguments: [:]), context: context
        )
        XCTAssertEqual(result.text, "[]")
        XCTAssertFalse(result.isError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testPlanRejectsMutationsAndUnexpectedArguments() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let context = startResponse(test, allowsActions: false)
        let result = try await test.model.executeChromeTool(action(), context: context)
        XCTAssertTrue(result.isError)
        let unexpected = try await test.model.executeChromeTool(
            DevelopmentToolCall(name: VyronChromeTools.sessions, arguments: ["path": .string("/private")]),
            context: context
        )
        XCTAssertTrue(unexpected.isError)
        XCTAssertTrue(VyronChromeTools.definitions.filter(\.isReadOnly).allSatisfy {
            $0.name != VyronChromeTools.action
        })
    }

    func testStaleResponseAndScheduledTasksCannotAccessChrome() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let context = startResponse(test)
        let call = DevelopmentToolCall(name: VyronChromeTools.sessions, arguments: [:])
        test.model.isRunningScheduledTask = true
        let scheduled = try await test.model.executeChromeTool(call, context: context)
        XCTAssertTrue(scheduled.isError)
        test.model.isRunningScheduledTask = false
        test.model.foregroundRun.stop()
        test.model.beginTestForegroundResponse()
        do {
            _ = try await test.model.executeChromeTool(call, context: context)
            XCTFail("A stale generation accessed Chrome")
        } catch is CancellationError {
            // Expected: no connection or page read is started.
        }
    }

    func testActionRejectsFractionalIDsAndArbitraryCode() async throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let context = startResponse(test)
        var arguments = action().function.arguments
        arguments["tab_id"] = .number(1.5)
        let fractional = try await test.model.executeChromeTool(
            DevelopmentToolCall(name: VyronChromeTools.action, arguments: arguments), context: context
        )
        XCTAssertTrue(fractional.isError)
        arguments = action().function.arguments
        arguments["code"] = .string("document.cookie")
        let code = try await test.model.executeChromeTool(
            DevelopmentToolCall(name: VyronChromeTools.action, arguments: arguments), context: context
        )
        XCTAssertTrue(code.isError)
    }

    func testExplicitExtensionRequestsUseWorkTools() {
        XCTAssertTrue(VyronChromeTools.prefersExtension("Use the Chrome extension to read my connected tab"))
        XCTAssertFalse(VyronChromeTools.prefersExtension("Open Safari"))
    }

    private func action() -> DevelopmentToolCall {
        DevelopmentToolCall(name: VyronChromeTools.action, arguments: [
            "session_id": .string(UUID().uuidString), "tab_id": .number(1),
            "snapshot_id": .string(UUID().uuidString), "element_id": .number(1), "action": .string("click")
        ])
    }

    private func startResponse(
        _ test: VyronQueueTestHarness, allowsActions: Bool = true
    ) -> VyronChromeToolContext {
        var source = Conversation(title: "Chrome test", workspacePath: test.directory.path)
        source.mode = ComposerMode.agent.rawValue
        source.messages = [ChatMessage(role: "assistant", content: "Reading connected tabs")]
        test.model.conversations = [source]
        test.model.selectedConversationID = source.id
        let response = VyronResponseIdentity(
            generationID: UUID(), conversationID: source.id, messageID: source.messages[0].id
        )
        test.model.foregroundRun.begin(response)
        return VyronChromeToolContext(response: response, allowsActions: allowsActions)
    }
}
