import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

private actor SelectedConnectionProvider: ModelProvider {
    let names: [String]
    private(set) var requestedModels: [String] = []
    private var catalogContinuation: CheckedContinuation<Void, Never>?
    private var holdCatalog = false
    private(set) var catalogRequested = false

    init(names: [String]) { self.names = names }

    func holdModelList() { holdCatalog = true }
    func releaseModelList() { catalogContinuation?.resume(); catalogContinuation = nil }

    func models() async throws -> [LocalModel] {
        catalogRequested = true
        if holdCatalog { await withCheckedContinuation { catalogContinuation = $0 } }
        return names.map { LocalModel(name: $0, size: 0) }
    }

    func chat(model: String, messages: [ChatMessage], systemPrompt: String?, onToken: @escaping @Sendable (String) -> Void) async throws -> String {
        requestedModels.append(model)
        onToken("Selected connection replied")
        return "Selected connection replied"
    }

    func developmentModel(model: String, automaticModelSelection: Bool, effort: AgentEffort) async throws -> LocalModel {
        LocalModel(name: model, size: 0, capabilities: ["tools"])
    }

    func developmentStep(model: String, messages: [DevelopmentMessage], effort: AgentEffort, mode: DevelopmentMode) async throws -> DevelopmentStep {
        requestedModels.append(model)
        return DevelopmentStep(message: DevelopmentMessage(role: "assistant", content: "Plan from selected connection"))
    }

    // Preserve exact selected-model behavior with the native read-only parallel task catalog.
    func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode,
        externalTools: [DevelopmentExternalTool]
    ) async throws -> DevelopmentStep {
        guard externalTools.allSatisfy({
            ($0.name == "parallel_tasks" && $0.isReadOnly) || VyronWebTools.definitions.contains($0)
                || VyronSkillResourceTools.definitions.contains($0)
                || VyronChromeTools.definitions.contains($0)
                || VyronOfficeTools.definitions.contains($0)
        }) else {
            throw ModelProviderError.unsupportedTools
        }
        return try await developmentStep(model: model, messages: messages, effort: effort, mode: mode)
    }
}

@MainActor
final class AppModelConnectionTests: XCTestCase {
    @MainActor
    private struct Harness {
        let directory: URL
        let defaults: [VyronUserDefaultsKey: Any]
        static let defaultsKeys: [VyronUserDefaultsKey] = [
            .selectedLocalModel, .automaticModelSelection, .workspacePath, .recentWorkspacePaths
        ]
        let model: AppModel

        @MainActor
        func cleanUp() {
            model.stopGeneration()
            try? FileManager.default.removeItem(at: directory)
            for key in Self.defaultsKeys {
                if let previous = defaults[key] { UserDefaults.standard.set(previous, forKey: key.rawValue) }
                else { UserDefaults.standard.removeObject(forKey: key.rawValue) }
            }
        }
    }

    private func harness() throws -> Harness {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VyronConnectionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var defaults: [VyronUserDefaultsKey: Any] = [:]
        for key in Harness.defaultsKeys {
            defaults[key] = UserDefaults.standard.object(forKey: key.rawValue)
        }
        let model = AppModel(historyDirectory: directory)
        model.workspaceState.workspaceURL = nil
        model.composer.mode = .chat
        return Harness(directory: directory, defaults: defaults, model: model)
    }

    private func configure(_ model: AppModel, provider: any ModelProvider, name: String) {
        let profile = ModelConnectionProfile(name: "Selected server", kind: .openAICompatible, endpoint: "https://models.example.com/v1", selectedModel: name)
        model.modelSelection.connectionProfiles = [profile]
        model.modelSelection.activate(VyronModelConnectionActivation(
            id: profile.id, provider: provider, model: name, automaticallySelect: false
        ))
        model.modelSelection.models = [LocalModel(name: name, size: 0)]
        model.modelSelection.isConnected = true
    }

    func testChatUsesExactCustomModelAndSelectedProvider() async throws {
        let test = try harness()
        defer { test.cleanUp() }
        let provider = SelectedConnectionProvider(names: ["vendor/team/custom-model-q8"])
        configure(test.model, provider: provider, name: "vendor/team/custom-model-q8")
        test.model.composer.draft = "Say hello"
        XCTAssertTrue(test.model.canSend)
        test.model.send()
        for _ in 0..<500 where test.model.foregroundRun.isGenerating { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        let models = await provider.requestedModels
        XCTAssertFalse(models.isEmpty)
        XCTAssertTrue(models.allSatisfy { $0 == "vendor/team/custom-model-q8" })
        XCTAssertEqual(test.model.messages.last?.content, "Selected connection replied")
        XCTAssertTrue(test.model.statusMessage?.contains("Remote server") == true)
        XCTAssertNil(test.model.errorMessage)
    }

    func testCustomSelectionDoesNotOverwriteBuiltinPreferenceOrAliasModelIDs() throws {
        let test = try harness()
        defer { test.cleanUp() }
        UserDefaults.standard.set("local-coder:q4", forKey: VyronUserDefaultsKey.selectedLocalModel.rawValue)
        UserDefaults.standard.set(true, forKey: VyronUserDefaultsKey.automaticModelSelection.rawValue)
        configure(test.model, provider: SelectedConnectionProvider(names: ["vendor/model"]), name: "vendor/model")
        XCTAssertEqual(UserDefaults.standard.string(forKey: VyronUserDefaultsKey.selectedLocalModel.rawValue), "local-coder:q4")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: VyronUserDefaultsKey.automaticModelSelection.rawValue))
        XCTAssertFalse(test.model.modelSelection.modelNamesMatch("vendor/model", "vendor/model:latest"))
        XCTAssertFalse(test.model.modelSelection.isSelectedModel("vendor/model:latest"))
    }

    func testUnavailableCustomConnectionCannotFallBackToBuiltin() throws {
        let test = try harness()
        defer { test.cleanUp() }
        configure(test.model, provider: SelectedConnectionProvider(names: ["custom"]), name: "custom")
        test.model.modelSelection.configuredInferenceClient = nil
        XCTAssertNil(test.model.modelSelection.inferenceProvider)
        test.model.composer.draft = "Private project question"
        XCTAssertFalse(test.model.canSend)
        test.model.send()
        XCTAssertTrue(test.model.messages.isEmpty)
    }

    func testOldCatalogCannotReplaceModelsAfterConnectionChanges() async throws {
        let test = try harness()
        defer { test.cleanUp() }
        let oldProvider = SelectedConnectionProvider(names: ["old-model"])
        await oldProvider.holdModelList()
        configure(test.model, provider: oldProvider, name: "old-model")
        let oldRefresh = Task { await test.model.refreshModels() }
        for _ in 0..<500 {
            if await oldProvider.catalogRequested { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let nextProvider = SelectedConnectionProvider(names: ["new-model"])
        configure(test.model, provider: nextProvider, name: "new-model")
        await test.model.refreshModels()
        await oldProvider.releaseModelList()
        await oldRefresh.value
        XCTAssertEqual(test.model.modelSelection.models.map(\.name), ["new-model"])
        XCTAssertTrue(test.model.modelSelection.isConnected)
        XCTAssertFalse(test.model.modelSelection.isRefreshing)
    }

    func testUnreadableConnectionsStayPreservedWhenApplyingSettings() throws {
        let test = try harness()
        defer { test.cleanUp() }
        let file = test.directory.appendingPathComponent("model-connections.json")
        let original = Data("{broken".utf8)
        try original.write(to: file)
        let reopened = AppModel(historyDirectory: test.directory)
        XCTAssertNotNil(reopened.modelSelection.connectionError)
        XCTAssertThrowsError(try reopened.saveBuiltinModelSettings(ModelSettings(temperature: 0.5)))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
}
