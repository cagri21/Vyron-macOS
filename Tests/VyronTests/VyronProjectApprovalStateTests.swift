import Combine
import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronProjectApprovalStateTests: XCTestCase {
    func testMissingOrUnknownPreferenceKeepsExistingAutomaticReviewBehavior() throws {
        preparePreferences()
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        XCTAssertEqual(test.model.interactions.projectApprovalMode, .approveForMe)

        UserDefaults.standard.set("unknown-mode", forKey: VyronUserDefaultsKey.projectCommandApprovalMode.rawValue)
        let reopened = AppModel(historyDirectory: test.directory)
        defer { reopened.stopGeneration() }
        XCTAssertEqual(reopened.interactions.projectApprovalMode, .approveForMe)
    }

    func testChoosingApprovalModePersistsWithoutChangingChatOrWork() throws {
        preparePreferences()
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.model.composer.mode = .plan

        test.model.selectProjectApprovalMode(.fullAccess)

        XCTAssertEqual(test.model.interactions.projectApprovalMode, .fullAccess)
        XCTAssertEqual(test.model.composer.mode, .plan)
        XCTAssertEqual(UserDefaults.standard.string(forKey: VyronUserDefaultsKey.projectCommandApprovalMode.rawValue), "fullAccess")
        let reopened = AppModel(historyDirectory: test.directory)
        defer { reopened.stopGeneration() }
        XCTAssertEqual(reopened.interactions.projectApprovalMode, .fullAccess)

        test.model.newConversation()
        XCTAssertEqual(test.model.interactions.projectApprovalMode, .fullAccess)
    }

    func testActiveRunRejectsApprovalChanges() throws {
        preparePreferences()
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.model.selectProjectApprovalMode(.askForApproval)
        let response = test.model.beginTestForegroundResponse()

        XCTAssertFalse(test.model.canChangeProjectApprovalMode)
        test.model.selectProjectApprovalMode(.fullAccess)

        XCTAssertEqual(test.model.interactions.projectApprovalMode, .askForApproval)
        XCTAssertEqual(UserDefaults.standard.string(forKey: VyronUserDefaultsKey.projectCommandApprovalMode.rawValue), "askForApproval")
        test.model.foregroundRun.complete(response.generationID)
        test.model.selectProjectApprovalMode(.approveForMe)
        XCTAssertEqual(test.model.interactions.projectApprovalMode, .approveForMe)
    }

    func testForegroundOwnerChangeNotifiesViewsReadingApprovalAvailability() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        var observedChange = false
        let subscription = test.model.objectWillChange.sink { observedChange = true }
        defer { subscription.cancel() }

        XCTAssertTrue(test.model.canChangeProjectApprovalMode)
        test.model.beginTestForegroundResponse()

        XCTAssertTrue(observedChange)
        XCTAssertFalse(test.model.canChangeProjectApprovalMode)
    }

    func testApprovalChoiceDoesNotUnlockStartedConversationMode() throws {
        preparePreferences()
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        var conversation = Conversation(title: "Existing work", workspacePath: nil)
        conversation.mode = ComposerMode.plan.rawValue
        conversation.messages = [ChatMessage(role: "user", content: "Plan this change.")]
        test.model.conversations = [conversation]
        test.model.selectConversation(conversation.id)

        test.model.selectProjectApprovalMode(.fullAccess)
        test.model.composer.mode = .chat

        XCTAssertTrue(test.model.isConversationModeLocked)
        XCTAssertEqual(test.model.interactions.projectApprovalMode, .fullAccess)
        XCTAssertEqual(test.model.composer.mode, .plan)
        XCTAssertEqual(test.model.selectedConversation?.mode, ComposerMode.plan.rawValue)
    }

    private func preparePreferences() {
        let previous = UserDefaults.standard.string(forKey: VyronUserDefaultsKey.projectCommandApprovalMode.rawValue)
        UserDefaults.standard.removeObject(forKey: VyronUserDefaultsKey.projectCommandApprovalMode.rawValue)
        addTeardownBlock { @MainActor in
            if let previous { UserDefaults.standard.set(previous, forKey: VyronUserDefaultsKey.projectCommandApprovalMode.rawValue) }
            else { UserDefaults.standard.removeObject(forKey: VyronUserDefaultsKey.projectCommandApprovalMode.rawValue) }
        }
    }
}
