import Foundation
@testable import Vyron
import VyronCore

@MainActor
final class VyronQueueTestHarness {
    let directory: URL
    let model: AppModel
    let provider = VyronQueueTestProvider()
    private let defaults: [VyronUserDefaultsKey: Any]
    private static let defaultsKeys: [VyronUserDefaultsKey] = [
        .selectedLocalModel, .automaticModelSelection, .queueFollowUpMessages,
        .workspacePath, .recentWorkspacePaths, .selectedSidebarProjectPath
    ]

    init(balanceDependencies: VyronConnectionBalanceDependencies? = nil) {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("VyronQueueTests-\(UUID())")
        defaults = Self.defaultsKeys.reduce(into: [:]) { result, key in
            result[key] = UserDefaults.standard.object(forKey: key.rawValue)
        }
        model = AppModel(historyDirectory: directory, balanceDependencies: balanceDependencies)
        model.modelSelection.configuredInferenceClient = provider
        model.workspaceState.workspaceURL = nil
        model.workspaceState.selectedProjectPath = nil
        model.composer.mode = .chat
        model.modelSelection.models = [LocalModel(name: "queue-test", size: 1)]
        model.modelSelection.selectedModel = "queue-test"
        model.modelSelection.automaticModelSelection = false
        model.modelSelection.isConnected = true
        model.composer.queueMessages = true
    }

    func send(_ text: String) {
        model.composer.draft = text
        model.send()
    }

    func cleanUp() {
        model.stopGeneration()
        do { try FileManager.default.removeItem(at: directory) } catch {
            preconditionFailure("Could not remove test history: \(error)")
        }
        for key in Self.defaultsKeys {
            if let value = defaults[key] { UserDefaults.standard.set(value, forKey: key.rawValue) }
            else { UserDefaults.standard.removeObject(forKey: key.rawValue) }
        }
    }
}
