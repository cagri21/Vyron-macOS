import Foundation
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronScheduledAppModelTestHarness {
    let directory: URL
    let model: AppModel
    let provider: VyronScheduledTestProvider
    private let savedDefaults: [VyronUserDefaultsKey: Any]

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronScheduledAppTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
        var defaults: [VyronUserDefaultsKey: Any] = [:]
        for key in Self.defaultsKeys {
            defaults[key] = UserDefaults.standard.object(forKey: key.rawValue)
        }
        savedDefaults = defaults
        let provider = VyronScheduledTestProvider()
        self.provider = provider
        model = AppModel(historyDirectory: directory)
        model.modelSelection.activeConnectionID = UUID()
        model.modelSelection.configuredInferenceClient = provider
        model.composer.mode = .chat
        model.workspaceState.workspaceURL = nil
        model.workspaceState.selectedProjectPath = nil
        model.modelSelection.selectedModel = "saved-model"
        model.modelSelection.automaticModelSelection = false
        model.modelSelection.isConnected = true
        model.modelSelection.models = [LocalModel(name: "saved-model", size: 1)]
        let conversation = Conversation(title: "Current conversation", workspacePath: nil)
        model.conversations = [conversation]
        model.selectedConversationID = conversation.id
        model.composer.draft = "Keep this unsent draft."
    }

    func task() -> VyronScheduledTask {
        var task = VyronScheduledTaskTestHarness.task(startsAt: Date().addingTimeInterval(3_600))
        task.definition.context = model.scheduledTaskContext()
        return task
    }

    func persistedConversations() throws -> [Conversation] {
        try JSONDecoder().decode(
            [Conversation].self,
            from: Data(contentsOf: directory.appendingPathComponent("conversations.json"))
        )
    }

    func cleanUp() async throws {
        defer {
            for key in Self.defaultsKeys {
                if let value = savedDefaults[key] {
                    UserDefaults.standard.set(value, forKey: key.rawValue)
                } else {
                    UserDefaults.standard.removeObject(forKey: key.rawValue)
                }
            }
        }
        model.scheduledTasks.shutdown()
        model.stopGeneration()
        for _ in 0..<500 {
            await provider.cancelOutstanding()
            if model.scheduledTasks.activeTaskID == nil { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        guard model.scheduledTasks.activeTaskID == nil else { throw CancellationError() }
        await model.scheduledTasks.waitForCurrentRun()
        try FileManager.default.removeItem(at: directory)
    }

    private static let defaultsKeys: [VyronUserDefaultsKey] = [
        .selectedLocalModel, .automaticModelSelection, .workspacePath, .recentWorkspacePaths,
        .selectedSidebarProjectPath
    ]
}
