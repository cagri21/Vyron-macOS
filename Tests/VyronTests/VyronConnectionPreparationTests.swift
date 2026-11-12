import Foundation
import XCTest
@testable import Vyron
import VyronCore

@MainActor
final class VyronConnectionPreparationTests: XCTestCase {
    private func profile(kind: ModelProviderKind = .openAICompatible) -> ModelConnectionProfile {
        ModelConnectionProfile(
            name: "Saved connection",
            kind: kind,
            endpoint: kind == .ollama ? "http://127.0.0.1:11434" : "https://models.example.test/v1",
            selectedModel: kind == .ollama ? "qwen3-coder:30b" : "vendor/team/exact-model-q8",
            settings: ModelSettings(contextTokens: 16_384, maxOutputTokens: 2_048)
        )
    }

    private func harness(
        _ profile: ModelConnectionProfile,
        scheduledTasks: [VyronScheduledTask] = []
    ) throws -> VyronConnectionPreparationTestHarness {
        try VyronConnectionPreparationTestHarness(
            state: ModelConnectionState(
                profiles: [profile], activeConnectionID: profile.id, builtinSettings: ModelSettings(contextTokens: 8_192)
            ),
            scheduledTasks: scheduledTasks
        )
    }

    func testStartupLoadsSelectionWithoutCredentialAndPreparationDoesNotBlockUIState() async throws {
        let profile = profile()
        let test = try harness(profile)
        XCTAssertEqual(test.model.modelSelection.activeConnectionID, profile.id)
        XCTAssertEqual(test.model.modelSelection.activeConnectionProfile, profile)
        XCTAssertEqual(test.model.modelSelection.selectedModel, profile.selectedModel)
        XCTAssertEqual(test.model.modelSelection.builtinModelSettings.contextTokens, 8_192)
        XCTAssertFalse(test.model.modelSelection.automaticModelSelection)
        XCTAssertNil(test.model.modelSelection.configuredInferenceClient)
        XCTAssertNil(test.model.modelSelection.connectionError)

        let preparation = test.prepare()
        let started = await test.waitForReads(1)
        XCTAssertTrue(started)
        test.model.composer.draft = "The interface remains editable while credentials load."
        XCTAssertFalse(test.model.composer.draft.isEmpty)
        XCTAssertNil(test.model.modelSelection.configuredInferenceClient)
        let completed = await test.reader.complete(0, result: .success("fixture-startup-key"))
        XCTAssertTrue(completed)
        await preparation.value
        XCTAssertNotNil(test.model.modelSelection.configuredInferenceClient)
        XCTAssertEqual(test.model.modelSelection.selectedModel, "vendor/team/exact-model-q8")
        XCTAssertNil(test.model.modelSelection.connectionError)
        try await test.cleanUp()
    }

    func testChangedConnectionRevisionRejectsDelayedCredential() async throws {
        let test = try harness(profile())
        let preparation = test.prepare()
        let started = await test.waitForReads(1)
        XCTAssertTrue(started)
        test.model.modelSelection.connectionRevision = UUID()
        test.model.modelSelection.selectedModel = "new-selection"
        let completed = await test.reader.complete(0, result: .success("fixture-old-key"))
        XCTAssertTrue(completed)
        await preparation.value
        XCTAssertNil(test.model.modelSelection.configuredInferenceClient)
        XCTAssertEqual(test.model.modelSelection.selectedModel, "new-selection")
        XCTAssertNil(test.model.modelSelection.connectionError)
        try await test.cleanUp()
    }

    func testEditedProfileRejectsDelayedCredentialWithoutDependingOnRevisionChange() async throws {
        let test = try harness(profile())
        let preparation = test.prepare()
        let started = await test.waitForReads(1)
        XCTAssertTrue(started)
        test.model.modelSelection.connectionProfiles[0].endpoint = "https://replacement.example.test/v1"
        let completed = await test.reader.complete(0, result: .success("fixture-old-host-key"))
        XCTAssertTrue(completed)
        await preparation.value
        XCTAssertNil(test.model.modelSelection.configuredInferenceClient)
        XCTAssertEqual(test.model.modelSelection.activeConnectionProfile?.endpoint, "https://replacement.example.test/v1")
        XCTAssertNil(test.model.modelSelection.connectionError)
        try await test.cleanUp()
    }

    func testDeletedProfileRejectsDelayedCredentialAndItsFailure() async throws {
        let test = try harness(profile())
        let preparation = test.prepare()
        let started = await test.waitForReads(1)
        XCTAssertTrue(started)
        test.model.modelSelection.connectionProfiles = []
        test.model.modelSelection.activeConnectionID = nil
        let completed = await test.reader.complete(0, result: .failure(VyronLocalAuthError.credentialsUnavailable))
        XCTAssertTrue(completed)
        await preparation.value
        XCTAssertNil(test.model.modelSelection.configuredInferenceClient)
        XCTAssertNil(test.model.modelSelection.connectionError)
        XCTAssertTrue(test.model.modelSelection.isBuiltinConnection)
        try await test.cleanUp()
    }

    func testCancellationAndShutdownRejectCredentialCompletion() async throws {
        for shutsDown in [false, true] {
            let test = try harness(profile())
            let preparation = test.prepare()
            let started = await test.waitForReads(1)
            XCTAssertTrue(started)
            if shutsDown { test.model.isShuttingDown = true }
            else { preparation.cancel() }
            let completed = await test.reader.complete(0, result: .success("fixture-cancelled-key"))
            XCTAssertTrue(completed)
            await preparation.value
            XCTAssertNil(test.model.modelSelection.configuredInferenceClient)
            XCTAssertNil(test.model.modelSelection.connectionError)
            try await test.cleanUp()
        }
    }

    func testReopenedWindowRetriesCancelledStartupAndStartsCatalogAndSchedules() async throws {
        let task = VyronScheduledTaskTestHarness.task(startsAt: .distantPast)
        let test = try harness(profile(), scheduledTasks: [task])
        addTeardownBlock { try await test.cleanUp() }
        let model = test.model
        model.scheduledTasks.configure(canRun: { true }) { _ in
            VyronScheduledTaskRunResult(state: .completed, conversationID: nil, detail: nil)
        }

        let closingWindow = test.start()
        guard await test.waitForReads(1) else {
            return XCTFail("The first window did not begin credential preparation.")
        }
        closingWindow.cancel()
        let reopenedWindow = test.start()
        let delivered = await test.reader.complete(0, result: .success("fixture-cancelled-key"))
        XCTAssertTrue(delivered)
        await closingWindow.value

        guard await test.waitForReads(2) else {
            return XCTFail("The reopened window did not retry credential preparation.")
        }
        XCTAssertNil(model.modelSelection.configuredInferenceClient)
        XCTAssertNil(model.scheduledTasks.tasks.first?.progress.lastRun)
        XCTAssertFalse(model.connectionBalances.isStarted)
        model.modelSelection.configuredInferenceClient = VyronScheduledTestProvider()
        let retried = await test.reader.complete(1, result: .success("fixture-reopened-key"))
        XCTAssertTrue(retried)
        await reopenedWindow.value
        await model.scheduledTasks.waitForCurrentRun()

        XCTAssertTrue(model.modelSelection.isConnected)
        XCTAssertTrue(model.modelSelection.models.contains { $0.name == "saved-model" })
        XCTAssertTrue(model.connectionBalances.isStarted)
        let firstRun = try XCTUnwrap(model.scheduledTasks.tasks.first?.progress.lastRun)
        XCTAssertEqual(firstRun.state, .completed)

        model.modelSelection.models = []
        await model.start()
        XCTAssertTrue(model.modelSelection.models.isEmpty, "Completed startup does not reload the catalog.")
        XCTAssertEqual(model.scheduledTasks.tasks.first?.progress.lastRun?.id, firstRun.id)
    }

    func testShutdownDuringStartupRejectsLateCredentialAndFurtherStartup() async throws {
        let task = VyronScheduledTaskTestHarness.task(startsAt: .distantPast)
        let test = try harness(profile(), scheduledTasks: [task])
        addTeardownBlock { try await test.cleanUp() }
        let model = test.model
        model.scheduledTasks.configure(canRun: { true }) { _ in
            VyronScheduledTaskRunResult(state: .completed, conversationID: nil, detail: nil)
        }

        let startup = test.start()
        guard await test.waitForReads(1) else {
            return XCTFail("Startup did not begin credential preparation.")
        }
        let shutdown = Task { await model.shutdownAsync() }
        guard await test.waitUntil({ model.isShuttingDown }) else {
            return XCTFail("Shutdown did not begin.")
        }
        let delivered = await test.reader.complete(0, result: .success("fixture-late-key"))
        XCTAssertTrue(delivered)
        await startup.value
        await shutdown.value

        await model.start { _ in
            XCTFail("Shutdown must reject further credential requests.")
            throw CancellationError()
        }
        XCTAssertNil(model.modelSelection.configuredInferenceClient)
        XCTAssertFalse(model.modelSelection.isConnected)
        XCTAssertFalse(model.connectionBalances.isStarted)
        XCTAssertNil(model.scheduledTasks.tasks.first?.progress.lastRun)
    }

    func testFailureLeavesSelectionAvailableForSuccessfulRetry() async throws {
        let profile = profile()
        let test = try harness(profile)
        let first = test.prepare()
        let firstStarted = await test.waitForReads(1)
        XCTAssertTrue(firstStarted)
        let firstCompleted = await test.reader.complete(0, result: .failure(VyronLocalAuthError.credentialsUnavailable))
        XCTAssertTrue(firstCompleted)
        await first.value
        XCTAssertNil(test.model.modelSelection.configuredInferenceClient)
        XCTAssertNotNil(test.model.modelSelection.connectionError)
        XCTAssertEqual(test.model.modelSelection.activeConnectionProfile, profile)

        let retry = test.prepare()
        let retryStarted = await test.waitForReads(2)
        XCTAssertTrue(retryStarted)
        let retryCompleted = await test.reader.complete(1, result: .success("fixture-retry-key"))
        XCTAssertTrue(retryCompleted)
        await retry.value
        XCTAssertNotNil(test.model.modelSelection.configuredInferenceClient)
        XCTAssertNil(test.model.modelSelection.connectionError)
        XCTAssertEqual(test.model.modelSelection.selectedModel, profile.selectedModel)
        try await test.cleanUp()
    }

    func testExistingProviderIsNotReplacedByDelayedStartup() async throws {
        let test = try harness(profile())
        let preparation = test.prepare()
        let started = await test.waitForReads(1)
        XCTAssertTrue(started)
        let replacement = OllamaClient()
        test.model.modelSelection.configuredInferenceClient = replacement
        let completed = await test.reader.complete(0, result: .success("fixture-obsolete-key"))
        XCTAssertTrue(completed)
        await preparation.value
        XCTAssertTrue((test.model.modelSelection.configuredInferenceClient as? OllamaClient) === replacement)
        try await test.cleanUp()
    }

    func testConfiguredOllamaKeepsExactQwenSelectionAndLocalSettings() async throws {
        let profile = profile(kind: .ollama)
        let test = try harness(profile)
        let preparation = test.prepare()
        let started = await test.waitForReads(1)
        XCTAssertTrue(started)
        let completed = await test.reader.complete(0, result: .success(""))
        XCTAssertTrue(completed)
        await preparation.value
        XCTAssertNotNil(test.model.modelSelection.configuredInferenceClient)
        XCTAssertEqual(test.model.modelSelection.activeConnectionProfile, profile)
        XCTAssertEqual(test.model.modelSelection.selectedModel, "qwen3-coder:30b")
        XCTAssertEqual(test.model.modelSelection.builtinModelSettings.contextTokens, 8_192)
        XCTAssertNil(test.model.modelSelection.connectionError)
        try await test.cleanUp()
    }

    func testBuiltinOllamaDoesNotReadCredentialsOrInstallRemoteProvider() async throws {
        let test = try VyronConnectionPreparationTestHarness(state: ModelConnectionState(
            builtinSettings: ModelSettings(contextTokens: 8_192)
        ))
        let selected = test.model.modelSelection.selectedModel
        let preparation = test.prepare()
        await preparation.value
        let requested = await test.reader.requests
        XCTAssertTrue(requested.isEmpty)
        XCTAssertNil(test.model.modelSelection.configuredInferenceClient)
        XCTAssertNil(test.model.modelSelection.activeConnectionID)
        XCTAssertEqual(test.model.modelSelection.selectedModel, selected)
        XCTAssertEqual(test.model.modelSelection.builtinModelSettings.contextTokens, 8_192)
        try await test.cleanUp()
    }
}
