import Foundation
import XCTest
@testable import Vyron
import VyronModelData
import VyronModelDomain

@MainActor
final class VyronModelSelectionModelTests: XCTestCase {
    func testPreparingAStoredRemoteUsesInjectedFactoryAfterReadingItsKey() async throws {
        let remote = VyronFeatureTestProvider()
        let profile = ModelConnectionProfile(
            name: "Fixture", kind: .openAICompatible, endpoint: "https://models.example.test/v1",
            selectedModel: "vendor/exact-model"
        )
        let key = "fixture-startup-key"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var constructionCount = 0
        let selection = VyronModelSelectionModel(
            builtinClient: OllamaClient(),
            store: ModelConnectionStore(fileURL: directory.appendingPathComponent("model-connections.json")),
            preferences: VyronBuiltinModelPreferences(defaults: .standard),
            providers: VyronModelProviderBuilders(
                builtin: { settings in try OllamaClient(settings: settings) },
                configured: { requested, credential in
                    constructionCount += 1
                    XCTAssertEqual(requested, profile)
                    XCTAssertEqual(credential, key)
                    return remote
                }
            )
        )
        selection.connectionProfiles = [profile]
        selection.activate(VyronModelConnectionActivation(
            id: profile.id, provider: nil, model: profile.selectedModel, automaticallySelect: false
        ))
        XCTAssertNil(selection.inferenceProvider)
        XCTAssertEqual(constructionCount, 0)

        await selection.prepareActiveConnection(readKey: { id in
            XCTAssertEqual(id, profile.id)
            return key
        }, canApply: { true })

        XCTAssertEqual(constructionCount, 1)
        XCTAssertEqual(selection.selectedModel, profile.selectedModel)
        XCTAssertTrue((selection.inferenceProvider as? VyronFeatureTestProvider) === remote)
    }
}
