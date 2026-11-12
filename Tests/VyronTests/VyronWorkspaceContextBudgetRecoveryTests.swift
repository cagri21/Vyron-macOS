import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronWorkspaceContextBudgetRecoveryTests: XCTestCase {
    func testBuiltInWorkBudgetFailureOffersSettingsUntilErrorChanges() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let route = try await projectRoute(for: test)
        let response = beginResponse(in: test.model)

        await test.model.failConversationRun(DevelopmentAgentError.contextBudget, route: route, response: response)

        XCTAssertEqual(test.model.errorMessage, DevelopmentAgentError.contextBudget.localizedDescription)
        XCTAssertEqual(test.model.workspaceError?.showsLocalContextBudgetHelp, true)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .failed)

        test.model.errorMessage = "A different workspace error"

        XCTAssertEqual(test.model.workspaceError?.message, "A different workspace error")
        XCTAssertEqual(test.model.workspaceError?.showsLocalContextBudgetHelp, false)

        test.model.errorMessage = nil

        XCTAssertNil(test.model.workspaceError)
    }

    func testHostedWorkBudgetFailureDoesNotOfferLocalSettings() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.select(test.profile(endpoint: "https://api.example.com/v1"), provider: test.provider)
        let route = try await projectRoute(for: test)
        let response = beginResponse(in: test.model)

        await test.model.failConversationRun(DevelopmentAgentError.contextBudget, route: route, response: response)

        XCTAssertEqual(test.model.errorMessage, DevelopmentAgentError.contextBudget.localizedDescription)
        XCTAssertEqual(test.model.workspaceError?.showsLocalContextBudgetHelp, false)
    }

    func testOnlyWorkBudgetFailuresOfferLocalSettings() async throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let route = try await projectRoute(for: test)
        let workResponse = beginResponse(in: test.model)

        await test.model.failConversationRun(DevelopmentAgentError.invalidGoal, route: route, response: workResponse)

        XCTAssertEqual(test.model.workspaceError?.showsLocalContextBudgetHelp, false)

        let chatResponse = beginResponse(in: test.model)
        await test.model.failConversationRun(DevelopmentAgentError.contextBudget, route: .chat, response: chatResponse)

        XCTAssertEqual(test.model.workspaceError?.showsLocalContextBudgetHelp, false)
    }

    private func projectRoute(for test: VyronFeatureTestHarness) async throws -> VyronConversationFailureRoute {
        await test.model.loadWorkspace(test.project)
        let workspace = try XCTUnwrap(test.model.workspaceState.developmentWorkspace)
        return .project(.init(workspace: workspace, url: test.model.workspaceState.workspaceURL))
    }

    private func beginResponse(in model: AppModel) -> VyronResponseIdentity {
        let message = ChatMessage(role: "assistant", content: "", activity: ResponseActivity())
        var conversation = Conversation(
            title: "Budget recovery", workspacePath: model.workspaceState.workspaceURL?.path
        )
        conversation.messages = [message]
        model.conversations = [conversation]
        model.selectedConversationID = conversation.id
        let response = VyronResponseIdentity(
            generationID: UUID(), conversationID: conversation.id, messageID: message.id
        )
        model.foregroundRun.begin(response, balanceConnectionID: nil)
        return response
    }
}
