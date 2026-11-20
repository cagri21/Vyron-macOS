import Foundation
import XCTest
@testable import Vyron
import VyronModelDomain

@MainActor
final class VyronAutoLocalAppTestHarness {
    let directory: URL
    let model: AppModel
    let assessment = VyronAutoLocalAppTestAssessment()
    let local = VyronAutoLocalAppTestProvider()
    let hosted = VyronAutoLocalAppTestProvider()
    let profile = ModelConnectionProfile(
        name: "Saved frontier", kind: .openAICompatible,
        endpoint: "https://models.example/v1", selectedModel: "frontier-test"
    )
    private let suite = "VyronAutoLocalAppTests." + UUID().uuidString

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let assessment = self.assessment
        let hosted = self.hosted
        let services = VyronAutoLocalServices(
            makeProvider: { profile in
                await assessment.recordBuild(profile.id)
                return hosted
            },
            assess: { _, request in try await assessment.assess(request) }
        )
        model = AppModel(
            storagePaths: VyronAppStoragePaths(directory: directory),
            preferences: preferences,
            modelOverrides: VyronAppModelOverrides(autoLocal: services)
        )
        model.workspaceState.workspaceURL = nil
        model.workspaceState.selectedProjectPath = nil
        model.modelSelection.activeConnectionID = nil
        model.modelSelection.configuredInferenceClient = local
        model.modelSelection.models = [LocalModel(name: "qwen3:4b", size: 2_500_000_000)]
        model.modelSelection.connectionProfiles = [profile]
        try model.modelSelection.useAutoLocalSelection()
        model.modelSelection.isConnected = true
        model.composer.mode = .chat
        model.composer.effort = .automatic
        model.computerWork.automaticRequestRouting = false
        model.skillContextLoader = { _ in .empty }
    }

    func send(_ prompt: String) {
        model.composer.draft = prompt
        XCTAssertTrue(model.canSend)
        model.send()
    }

    func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Auto Local did not reach its expected state")
        throw CancellationError()
    }

    func cleanUp() {
        model.stopGeneration()
        model.cancelModelFeatureVerification()
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        do { try FileManager.default.removeItem(at: directory) } catch {
            XCTFail("Could not remove Auto Local fixture: \(error)")
        }
    }
}
