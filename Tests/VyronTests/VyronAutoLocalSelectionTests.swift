import Foundation
import XCTest
@testable import Vyron
import VyronModelData
import VyronModelDomain

@MainActor
final class VyronAutoLocalSelectionTests: XCTestCase {
    func testExistingPreferencesKeepLocalOnlyAutoUntilEnabled() throws {
        let selection = try makeSelection()

        XCTAssertTrue(selection.automaticModelSelection)
        XCTAssertFalse(selection.localFirstRouting)
        XCTAssertFalse(selection.isAutoLocalEnabled)
    }

    func testLocalHelperCanEnableAndPersistAutoLocalWithoutACodingModel() throws {
        let helper = LocalModel(name: "qwen3:4b", size: 2_500_000_000, capabilities: ["completion"])
        let selection = try makeSelection(models: [helper])

        try selection.useAutoLocalSelection()

        XCTAssertEqual(selection.selectedModel, helper.name)
        XCTAssertTrue(selection.isAutoLocalEnabled)
        XCTAssertTrue(selection.preferences.localFirstRouting)
        XCTAssertTrue(selection.preferences.automaticallySelect)
    }

    func testUnavailableAssessorDoesNotEnableAutoLocal() throws {
        let selection = try makeSelection()

        XCTAssertThrowsError(try selection.useAutoLocalSelection())

        XCTAssertFalse(selection.isAutoLocalEnabled)
        XCTAssertFalse(selection.preferences.localFirstRouting)
    }

    func testManualModelAndRegularAutoDisableLocalFirstRouting() throws {
        let local = LocalModel(name: "qwen3:4b", size: 2_500_000_000, capabilities: ["completion"])
        let selection = try makeSelection(models: [local])
        try selection.useAutoLocalSelection()

        _ = try selection.selectInstalledModel(local.name, readKey: { _ in
            XCTFail("Selecting an installed local model must not read a provider credential")
            return ""
        })
        XCTAssertFalse(selection.localFirstRouting)
        XCTAssertFalse(selection.automaticModelSelection)

        try selection.useAutoLocalSelection()
        try selection.useAutomaticSelection(forChat: true)
        XCTAssertFalse(selection.localFirstRouting)
        XCTAssertTrue(selection.automaticModelSelection)
    }

    func testHostedActivationSuspendsAutoLocalAndRetainsItsLocalPreference() throws {
        let helper = LocalModel(name: "qwen3:4b", size: 2_500_000_000, capabilities: ["completion"])
        let selection = try makeSelection(models: [helper])
        try selection.useAutoLocalSelection()
        let localActivation = selection.builtinActivation

        selection.activate(VyronModelConnectionActivation(
            id: UUID(), provider: nil, model: "saved-model", automaticallySelect: false
        ))

        XCTAssertFalse(selection.isAutoLocalEnabled)
        XCTAssertTrue(selection.preferences.localFirstRouting)
        selection.activate(localActivation)
        XCTAssertTrue(selection.isAutoLocalEnabled)
    }

    private func makeSelection(models: [LocalModel] = []) throws -> VyronModelSelectionModel {
        let suiteName = "VyronAutoLocalSelectionTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let selection = VyronModelSelectionModel(
            builtinClient: OllamaClient(),
            store: ModelConnectionStore(fileURL: directory.appendingPathComponent("model-connections.json")),
            preferences: VyronBuiltinModelPreferences(defaults: defaults),
            providers: VyronModelProviderBuilders(
                builtin: { try OllamaClient(settings: $0) },
                configured: { try VyronModelProviderFactory.makeProvider(for: $0, apiKey: $1) }
            )
        )
        selection.models = models
        return selection
    }
}
