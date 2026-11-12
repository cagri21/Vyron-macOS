import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronResponseSpeedSelectionTests: XCTestCase {
    func testSpeedSelectionPersistsAndReplacesOnlyTheMainProviderWithoutChangingEffortOrDraft() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let profile = test.profile(modelName: "gpt-6.1-sol", endpoint: "https://api.openai.com/v1")
        test.select(profile, provider: test.provider, capabilities: ["tools"])
        test.model.composer.mode = .plan
        test.model.composer.effort = .maximum
        test.model.composer.draft = "Keep the task and effort unchanged."
        let selection = test.model.modelFeatureSelection(for: profile)
        test.model.recordModelToolVerification(.verified, selection: selection)
        try test.model.connectionBalances.setEstimatedBalance(10, for: profile.id)
        let capturedProvider = test.model.modelSelection.inferenceProvider
        let replacement = VyronFeatureTestProvider()
        var constructions = 0
        XCTAssertTrue(test.model.selectResponseSpeed(.fast, providerBuilder: { updated in
            constructions += 1
            XCTAssertEqual(updated.settings.responseSpeed, .fast)
            XCTAssertEqual(updated.id, profile.id)
            XCTAssertEqual(updated.selectedModel, profile.selectedModel)
            return replacement
        }))
        XCTAssertEqual(constructions, 1)
        XCTAssertEqual(test.model.responseSpeed, .fast)
        XCTAssertEqual(test.model.composer.effort, .maximum)
        XCTAssertEqual(test.model.composer.mode, .plan)
        XCTAssertEqual(test.model.modelSelection.selectedModel, profile.selectedModel)
        XCTAssertEqual(test.model.composer.draft, "Keep the task and effort unchanged.")
        XCTAssertTrue((capturedProvider as? VyronFeatureTestProvider) === test.provider)
        XCTAssertTrue((test.model.modelSelection.inferenceProvider as? VyronFeatureTestProvider) === replacement)
        XCTAssertEqual(test.model.modelFeatureReport[.agent].status, .available)
        XCTAssertEqual(test.model.connectionBalances.estimatedBalance(for: profile.id)?.remainingUSD, 10)
        let saved = try test.model.modelSelection.store.load()
        XCTAssertEqual(saved.profiles.first?.settings.responseSpeed, .fast)
        XCTAssertEqual(saved.profiles.first?.id, profile.id)
        XCTAssertEqual(saved.activeConnectionID, profile.id)
        XCTAssertTrue(test.model.selectResponseSpeed(.standard, providerBuilder: { _ in replacement }))
        XCTAssertEqual(test.model.responseSpeed, .standard)
        XCTAssertEqual(try test.model.modelSelection.store.load().profiles.first?.settings.responseSpeed, .standard)
        XCTAssertEqual(test.model.composer.effort, .maximum)
    }

    func testFailedConstructionOrSaveLeavesPreviousSelectionAndProviderIntact() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let profile = test.profile(modelName: "gpt-6.1-sol", endpoint: "https://api.openai.com/v1")
        test.select(profile, provider: test.provider)
        let revision = test.model.modelSelection.connectionRevision
        XCTAssertFalse(test.model.selectResponseSpeed(.fast, providerBuilder: { _ in
            throw ModelProviderError.connectionFailed
        }))
        XCTAssertEqual(test.model.modelSelection.connectionProfiles, [profile])
        XCTAssertEqual(test.model.modelSelection.connectionRevision, revision)
        XCTAssertEqual(test.model.responseSpeed, .standard)
        XCTAssertTrue((test.model.modelSelection.inferenceProvider as? VyronFeatureTestProvider) === test.provider)
        XCTAssertNotNil(test.model.modelSelection.connectionError)
        test.model.modelSelection.modelConnectionsWritable = false
        let replacement = VyronFeatureTestProvider()
        XCTAssertFalse(test.model.selectResponseSpeed(.fast, providerBuilder: { _ in replacement }))
        XCTAssertEqual(test.model.modelSelection.connectionProfiles, [profile])
        XCTAssertEqual(test.model.modelSelection.connectionRevision, revision)
        XCTAssertEqual(test.model.responseSpeed, .standard)
        XCTAssertTrue((test.model.modelSelection.inferenceProvider as? VyronFeatureTestProvider) === test.provider)
    }

    func testBusyAndUnsupportedSelectionsNeverConstructAProviderOrChangeSpeed() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        var profile = test.profile(modelName: "gpt-6.1-sol", endpoint: "https://api.openai.com/v1")
        test.select(profile, provider: test.provider)
        var constructions = 0
        let builder: @MainActor (ModelConnectionProfile) throws -> any ModelProvider = { _ in
            constructions += 1
            return test.provider
        }
        XCTAssertTrue(test.model.selectResponseSpeed(.standard, providerBuilder: builder))
        XCTAssertEqual(constructions, 0)
        let response = test.model.beginTestForegroundResponse()
        XCTAssertFalse(test.model.selectResponseSpeed(.fast, providerBuilder: builder))
        test.model.foregroundRun.complete(response.generationID)
        VyronModelTransferFixture.start(in: test.model.modelDownloads)
        XCTAssertFalse(test.model.selectResponseSpeed(.fast, providerBuilder: builder))
        test.model.modelDownloads.cancel()
        test.model.isShuttingDown = true
        XCTAssertFalse(test.model.selectResponseSpeed(.fast, providerBuilder: builder))
        test.model.isShuttingDown = false
        profile.endpoint = "http://localhost:1234/v1"
        test.select(profile, provider: test.provider)
        XCTAssertFalse(test.model.supportsFastResponses)
        XCTAssertFalse(test.model.selectResponseSpeed(.fast, providerBuilder: builder))
        XCTAssertEqual(constructions, 0)
        XCTAssertEqual(test.model.responseSpeed, .standard)
    }

    func testDifferentConnectionOrUnknownModelDoesNotBorrowFastFromAnotherSelection() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        var first = test.profile(modelName: "gpt-6.1-sol", endpoint: "https://api.openai.com/v1")
        first.settings.responseSpeed = .fast
        let second = test.profile(modelName: "gpt-6.1-sol", endpoint: "https://api.openai.com/v1")
        test.select(first, provider: test.provider)
        test.model.modelSelection.connectionProfiles = [first, second]
        XCTAssertEqual(test.model.responseSpeed, .fast)
        test.model.modelSelection.activeConnectionID = second.id
        XCTAssertEqual(test.model.responseSpeed, .standard)
        test.model.modelSelection.activeConnectionID = first.id
        XCTAssertEqual(test.model.responseSpeed, .fast)
        test.model.modelSelection.selectedModel = "unverified-future-model"
        XCTAssertFalse(test.model.supportsFastResponses)
        XCTAssertEqual(test.model.responseSpeed, .standard)
        test.model.modelSelection.activeConnectionID = nil
        XCTAssertEqual(test.model.responseSpeed, .standard)
    }

    func testEditingOtherModelSettingsPreservesTheSavedResponseSpeed() throws {
        var settings = ModelSettings(contextTokens: 32_768, maxOutputTokens: 4_096)
        settings.responseSpeed = .fast
        var draft = VyronModelSettingsDraft(settings)
        draft.budget.maxOutputTokens = "2048"
        let edited = try draft.settings(thinkingSupport: .providerDefaultOnly)
        XCTAssertEqual(edited.responseSpeed, .fast)
        XCTAssertEqual(edited.contextTokens, 32_768)
        XCTAssertEqual(edited.maxOutputTokens, 2_048)
    }
}
