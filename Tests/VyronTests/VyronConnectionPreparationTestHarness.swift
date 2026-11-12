import Foundation
@testable import Vyron
import VyronCore

@MainActor
struct VyronConnectionPreparationTestHarness {
    let model: AppModel
    let reader = VyronConnectionPreparationTestReader()
    private let directory: URL
    private let defaults: [VyronUserDefaultsKey: Any]

    init(state: ModelConnectionState, scheduledTasks: [VyronScheduledTask] = []) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronConnectionPreparation-\(UUID().uuidString)", isDirectory: true)
        var saved: [VyronUserDefaultsKey: Any] = [:]
        for key in Self.defaultKeys {
            saved[key] = UserDefaults.standard.object(forKey: key.rawValue)
        }
        defaults = saved
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try ModelConnectionStore(fileURL: directory.appendingPathComponent("model-connections.json")).save(state)
        if !scheduledTasks.isEmpty {
            try VyronScheduledTaskStore(fileURL: directory.appendingPathComponent("scheduled-tasks.json"))
                .save(scheduledTasks)
        }
        model = AppModel(historyDirectory: directory)
        model.workspaceState.workspaceURL = nil
    }

    func prepare() -> Task<Void, Never> {
        let model = model
        let reader = reader
        return Task {
            await model.prepareActiveModelConnection { id in try await reader.read(id) }
        }
    }

    func start() -> Task<Void, Never> {
        let model = model
        let reader = reader
        return Task {
            await model.start { id in try await reader.read(id) }
        }
    }

    func waitForReads(_ expected: Int) async -> Bool {
        await waitUntil { await reader.requests.count == expected }
    }

    func waitUntil(_ condition: @MainActor () async -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if await condition() { return true }
            do { try await Task.sleep(for: .milliseconds(5)) } catch { return false }
        }
        return await condition()
    }

    func cleanUp() async throws {
        let starting = model.startup.shutdown()
        model.stopGeneration()
        model.localAuthentication.shutdown()
        model.connectionBalances.shutdown()
        model.modelSelection.shutdown()
        model.cancelModelFeatureVerification()
        model.scheduledTasks.shutdown()
        await reader.cancelAll()
        await starting?.value
        defer {
            for key in Self.defaultKeys {
                if let value = defaults[key] { UserDefaults.standard.set(value, forKey: key.rawValue) }
                else { UserDefaults.standard.removeObject(forKey: key.rawValue) }
            }
        }
        try FileManager.default.removeItem(at: directory)
    }

    private static var defaultKeys: [VyronUserDefaultsKey] {
        [.selectedLocalModel, .automaticModelSelection, .workspacePath, .recentWorkspacePaths]
    }
}
