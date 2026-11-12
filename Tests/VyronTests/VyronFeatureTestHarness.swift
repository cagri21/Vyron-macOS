import Foundation
import XCTest
@testable import Vyron
import VyronCore

@MainActor
final class VyronFeatureTestHarness {
    let directory: URL
    let project: URL
    let model: AppModel
    let provider = VyronFeatureTestProvider()
    private let savedDefaults: [VyronUserDefaultsKey: Any]

    private static let defaultsKeys: [VyronUserDefaultsKey] = [
        .selectedLocalModel, .automaticModelSelection, .workspacePath, .recentWorkspacePaths,
        .selectedSidebarProjectPath
    ]

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronFeatureTests-\(UUID())", isDirectory: true)
        project = directory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("A local test project.\n".utf8).write(to: project.appendingPathComponent("README.md"))
        savedDefaults = Self.defaultsKeys.reduce(into: [:]) { values, key in
            values[key] = UserDefaults.standard.object(forKey: key.rawValue)
        }
        model = AppModel(historyDirectory: directory)
        model.modelSelection.isConnected = false
        model.workspaceState.workspaceURL = nil
        model.workspaceState.selectedProjectPath = nil
        model.composer.mode = .chat
        model.modelSelection.automaticModelSelection = false
    }

    func select(
        _ profile: ModelConnectionProfile,
        provider: any ModelProvider,
        capabilities: [String]? = nil
    ) {
        model.modelSelection.isConnected = false
        model.modelSelection.connectionRevision = UUID()
        model.modelSelection.connectionProfiles = [profile]
        model.modelSelection.activeConnectionID = profile.id
        model.modelSelection.configuredInferenceClient = provider
        model.modelSelection.automaticModelSelection = false
        model.modelSelection.models = [LocalModel(name: profile.selectedModel, size: 1, capabilities: capabilities)]
        model.modelSelection.selectedModel = profile.selectedModel
        model.modelSelection.isConnected = true
    }

    func profile(modelName: String = "shared-model", endpoint: String = "http://localhost:1234/v1")
        -> ModelConnectionProfile {
        ModelConnectionProfile(
            name: "Feature test server", kind: .openAICompatible, endpoint: endpoint, selectedModel: modelName
        )
    }

    func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The in-memory capability operation did not finish.")
        throw CancellationError()
    }

    func cleanUp() {
        model.cancelModelFeatureVerification()
        model.stopGeneration()
        do { try FileManager.default.removeItem(at: directory) } catch {
            XCTFail("Could not remove capability test files: \(error)")
        }
        for key in Self.defaultsKeys {
            if let value = savedDefaults[key] { UserDefaults.standard.set(value, forKey: key.rawValue) }
            else { UserDefaults.standard.removeObject(forKey: key.rawValue) }
        }
    }
}
