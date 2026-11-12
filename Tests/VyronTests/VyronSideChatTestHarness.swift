import Foundation
import XCTest
@testable import Vyron
import VyronCore

@MainActor
final class VyronSideChatTestHarness {
    let directory: URL
    let model: AppModel
    let provider = VyronSideChatTestProvider()
    private let savedDefaults: [VyronUserDefaultsKey: Any]

    private static let defaultsKeys: [VyronUserDefaultsKey] = [
        .selectedLocalModel, .automaticModelSelection, .workspacePath, .recentWorkspacePaths,
        .selectedSidebarProjectPath
    ]

    init(balanceDependencies: VyronConnectionBalanceDependencies? = nil) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronSideChatTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        savedDefaults = Self.defaultsKeys.reduce(into: [:]) { values, key in
            values[key] = UserDefaults.standard.object(forKey: key.rawValue)
        }
        model = AppModel(historyDirectory: directory, balanceDependencies: balanceDependencies)
        model.modelSelection.isConnected = false
        model.workspaceState.workspaceURL = nil
        model.workspaceState.selectedProjectPath = nil
        model.modelSelection.automaticModelSelection = false
        model.computerWork.automaticRequestRouting = false
        model.modelSelection.configuredInferenceClient = provider
        model.modelSelection.selectedModel = "side-chat-test-model"
        model.modelSelection.models = [LocalModel(name: "side-chat-test-model", size: 1)]
        model.composer.mode = .chat
        var source = Conversation(title: "Original task", workspacePath: nil)
        source.mode = ComposerMode.chat.rawValue
        source.messages = [ChatMessage(role: "user", content: "Keep the original task and its evidence intact.")]
        model.conversations = [source]
        model.selectedConversationID = source.id
        model.modelSelection.isConnected = true
        guard model.saveHistory() else { throw CocoaError(.fileWriteUnknown) }
    }

    func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The in-memory side-chat operation did not finish.")
        throw CancellationError()
    }

    func makeHistoryUnwritable() throws {
        let history = directory.appendingPathComponent("conversations.json")
        try FileManager.default.removeItem(at: history)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: false)
    }

    func cleanUp() async {
        let tasks = model.stopSideChatsForShutdown()
        model.stopGeneration()
        model.cancelModelFeatureVerification()
        await provider.finishAll()
        for task in tasks { await task.value }
        do { try FileManager.default.removeItem(at: directory) } catch {
            XCTFail("Could not remove side-chat fixture files: \(error)")
        }
        for key in Self.defaultsKeys {
            if let value = savedDefaults[key] { UserDefaults.standard.set(value, forKey: key.rawValue) }
            else { UserDefaults.standard.removeObject(forKey: key.rawValue) }
        }
    }
}
