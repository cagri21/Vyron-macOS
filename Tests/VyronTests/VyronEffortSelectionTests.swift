import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronEffortSelectionTests: XCTestCase {
    func testSelectingAndResettingEffortPreservesExactModelConnectionModeAndSettings() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        var profile = test.profile(modelName: "exact-selected-model:q4")
        profile.settings = ModelSettings(contextTokens: 32_768, maxOutputTokens: 4_096, temperature: 0.3, topP: 0.75)
        test.select(profile, provider: test.provider, capabilities: ["tools"])
        test.model.workspaceState.workspaceURL = test.project
        test.model.workspaceState.selectedProjectPath = test.project.path
        test.model.composer.mode = .plan
        test.model.modelSelection.builtinModelSettings = ModelSettings(contextTokens: 16_384, maxOutputTokens: 2_048, thinking: false)
        test.model.composer.draft = "Preserve this unsent task."
        let selectedModel = test.model.modelSelection.selectedModel
        let connectionID = test.model.modelSelection.activeConnectionID
        let profiles = test.model.modelSelection.connectionProfiles
        let builtinSettings = test.model.modelSelection.builtinModelSettings
        let revision = test.model.modelSelection.connectionRevision

        for effort in AgentEffort.allCases {
            XCTAssertTrue(test.model.selectDevelopmentEffort(effort))
            XCTAssertEqual(test.model.composer.effort, effort)
            XCTAssertEqual(test.model.modelSelection.selectedModel, selectedModel)
            XCTAssertEqual(test.model.modelSelection.activeConnectionID, connectionID)
            XCTAssertEqual(test.model.modelSelection.connectionProfiles, profiles)
            XCTAssertEqual(test.model.modelSelection.builtinModelSettings, builtinSettings)
            XCTAssertEqual(test.model.modelSelection.connectionRevision, revision)
            XCTAssertFalse(test.model.modelSelection.automaticModelSelection)
            XCTAssertEqual(test.model.composer.mode, .plan)
            XCTAssertEqual(test.model.workspaceState.workspaceURL, test.project)
            XCTAssertEqual(test.model.workspaceState.selectedProjectPath, test.project.path)
            XCTAssertEqual(test.model.composer.draft, "Preserve this unsent task.")
            XCTAssertTrue((test.model.modelSelection.configuredInferenceClient as? VyronFeatureTestProvider) === test.provider)
        }
    }

    func testAutomaticEffortDoesNotEnableAutomaticModelSelectionOrChangeManualChoice() {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.model.composer.effort = .ultra
        let selectedModel = test.model.modelSelection.selectedModel

        XCTAssertTrue(test.model.selectDevelopmentEffort(.automatic))

        XCTAssertEqual(test.model.composer.effort, .automatic)
        XCTAssertEqual(test.model.modelSelection.selectedModel, selectedModel)
        XCTAssertFalse(test.model.modelSelection.automaticModelSelection)
        XCTAssertEqual(test.model.composer.mode, .chat)
        XCTAssertTrue(test.model.messages.isEmpty)
    }

    func testDownloadingAndExistingModelSelectionBusyStatesRejectEffortChanges() async {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        test.model.composer.effort = .balanced
        let selectedModel = test.model.modelSelection.selectedModel
        VyronModelTransferFixture.start(in: test.model.modelDownloads)
        assertSelectionRefused(test.model)
        test.model.modelDownloads.cancel()
        test.model.beginTestForegroundResponse()
        assertSelectionRefused(test.model)
        test.model.foregroundRun.stop()
        test.model.modelSelection.connectionOperationInProgress = true
        assertSelectionRefused(test.model)
        test.model.modelSelection.connectionOperationInProgress = false
        test.model.modelSelection.isStarting = true
        assertSelectionRefused(test.model)
        test.model.modelSelection.isStarting = false
        test.model.computerWork.isComputerWorkActive = true
        assertSelectionRefused(test.model)
        test.model.computerWork.isComputerWorkActive = false
        await test.model.withTestDevelopmentSettlement {
            assertSelectionRefused(test.model)
        }
        test.model.computerWork.isPlanningControls = true
        assertSelectionRefused(test.model)
        test.model.computerWork.isPlanningControls = false
        test.model.isShuttingDown = true
        assertSelectionRefused(test.model)
        test.model.isShuttingDown = false

        XCTAssertEqual(test.model.composer.effort, .balanced)
        XCTAssertEqual(test.model.modelSelection.selectedModel, selectedModel)
        XCTAssertTrue(test.model.canSelectDevelopmentEffort)
        XCTAssertTrue(test.model.selectDevelopmentEffort(.quick))
        XCTAssertEqual(test.model.composer.effort, .quick)
    }

    func testActiveScheduledRunLocksEveryEffortAndResetAfterwardsKeepsItsCapturedContext() async throws {
        let test = try VyronScheduledAppModelTestHarness()
        addTeardownBlock { try await test.cleanUp() }
        test.model.composer.effort = .ultra
        let task = test.task()
        let selectedModel = test.model.modelSelection.selectedModel
        let connectionID = test.model.modelSelection.activeConnectionID
        let settings = test.model.modelSelection.builtinModelSettings
        let draft = test.model.composer.draft
        XCTAssertTrue(test.model.scheduledTasks.save(task))
        test.model.scheduledTasks.runNow(task.id)
        for _ in 0..<500 {
            if await test.provider.requests.count == 1 { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        let requests = await test.provider.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertNotNil(test.model.scheduledTasks.activeTaskID)
        for effort in AgentEffort.allCases {
            XCTAssertFalse(test.model.canSelectDevelopmentEffort)
            XCTAssertFalse(test.model.selectDevelopmentEffort(effort))
            XCTAssertEqual(test.model.composer.effort, .ultra)
        }
        XCTAssertEqual(test.model.modelSelection.selectedModel, selectedModel)
        XCTAssertEqual(test.model.modelSelection.activeConnectionID, connectionID)
        XCTAssertEqual(test.model.modelSelection.builtinModelSettings, settings)
        XCTAssertEqual(test.model.composer.draft, draft)
        XCTAssertEqual(test.model.scheduledTasks.tasks.first?.definition.context.model.effort, .ultra)
        await test.provider.complete("The captured scheduled task finished.")
        await test.model.scheduledTasks.waitForCurrentRun()

        XCTAssertTrue(test.model.selectDevelopmentEffort(.automatic))
        XCTAssertEqual(test.model.composer.effort, .automatic)
        XCTAssertEqual(test.model.modelSelection.selectedModel, selectedModel)
        XCTAssertEqual(test.model.modelSelection.activeConnectionID, connectionID)
        XCTAssertEqual(test.model.modelSelection.builtinModelSettings, settings)
        XCTAssertEqual(test.model.composer.draft, draft)
        XCTAssertEqual(test.model.scheduledTasks.tasks.first?.definition.context.model.effort, .ultra)
    }

    private func assertSelectionRefused(_ model: AppModel) {
        XCTAssertFalse(model.canSelectDevelopmentEffort)
        for effort in AgentEffort.allCases {
            XCTAssertFalse(model.selectDevelopmentEffort(effort))
            XCTAssertEqual(model.composer.effort, .balanced)
        }
    }
}
