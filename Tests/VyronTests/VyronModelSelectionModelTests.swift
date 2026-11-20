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

    func testSelectingAnOfficialOpenAIModelSwitchesProvidersOnlyWhenTransportChanges() throws {
        let compatible = "gpt-4.1"
        let sol = "gpt-6.2-sol"
        let astra = "gpt-6.2-astra"
        let key = "fixture-selection-key"
        var profile = VyronOpenAIConnectionPreset.makeProfile()
        profile.selectedModel = compatible
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let store = ModelConnectionStore(fileURL: directory.appendingPathComponent("model-connections.json"))
        let selection = VyronModelSelectionModel(
            builtinClient: OllamaClient(),
            store: store,
            preferences: VyronBuiltinModelPreferences(defaults: .standard),
            providers: VyronModelProviderBuilders(
                builtin: { settings in try OllamaClient(settings: settings) },
                configured: { requested, credential in
                    XCTAssertEqual(credential, key)
                    return try VyronModelProviderFactory.makeProvider(for: requested, apiKey: credential)
                }
            )
        )
        selection.connectionProfiles = [profile]
        let initialProvider = try selection.makeProvider(for: profile, apiKey: key)
        selection.activate(VyronModelConnectionActivation(
            id: profile.id,
            provider: initialProvider,
            model: compatible,
            automaticallySelect: false
        ))
        selection.models = [compatible, sol, astra].map { LocalModel(name: $0, size: 0) }
        XCTAssertTrue(selection.inferenceProvider is OpenAICompatibleClient)

        var keyReads: [UUID] = []
        func readKey(_ id: UUID) -> String {
            keyReads.append(id)
            return key
        }

        XCTAssertEqual(try selection.selectInstalledModel(sol, readKey: readKey).name, sol)
        let responses = try XCTUnwrap(selection.inferenceProvider as? VyronOpenAIResponsesClient)
        XCTAssertEqual(selection.selectedModel, sol)
        XCTAssertEqual(try store.load().profiles.first?.selectedModel, sol)
        XCTAssertEqual(keyReads, [profile.id])

        XCTAssertEqual(try selection.selectInstalledModel(astra, readKey: readKey).name, astra)
        XCTAssertTrue((selection.inferenceProvider as? VyronOpenAIResponsesClient) === responses)
        XCTAssertEqual(selection.selectedModel, astra)
        XCTAssertEqual(try store.load().profiles.first?.selectedModel, astra)
        XCTAssertEqual(keyReads, [profile.id])

        XCTAssertEqual(try selection.selectInstalledModel(compatible, readKey: readKey).name, compatible)
        XCTAssertTrue(selection.inferenceProvider is OpenAICompatibleClient)
        XCTAssertEqual(selection.selectedModel, compatible)
        XCTAssertEqual(try store.load(), ModelConnectionState(profiles: [profile], activeConnectionID: profile.id))
        XCTAssertEqual(keyReads, [profile.id, profile.id])
    }
}
