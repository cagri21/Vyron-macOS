import Foundation
import XCTest
@testable import Vyron
import VyronCore

@MainActor
final class VyronVoiceAppTestHarness {
    let voiceTest: VyronVoiceTestHarness
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VyronVoiceAppTests-\(UUID())")
    let model: AppModel
    let provider = VyronQueueTestProvider()
    private let defaults: [VyronUserDefaultsKey: Any]
    private static let defaultsKeys: [VyronUserDefaultsKey] = [
        .selectedLocalModel, .automaticModelSelection, .queueFollowUpMessages,
        .workspacePath, .recentWorkspacePaths
    ]

    init() throws {
        voiceTest = try VyronVoiceTestHarness()
        defaults = Self.defaultsKeys.reduce(into: [:]) { result, key in
            result[key] = UserDefaults.standard.object(forKey: key.rawValue)
        }
        model = AppModel(historyDirectory: directory, voice: voiceTest.model)
        model.modelSelection.configuredInferenceClient = provider
        model.workspaceState.workspaceURL = nil
        model.composer.mode = .chat
        model.modelSelection.models = [LocalModel(name: "queue-test", size: 1)]
        model.modelSelection.selectedModel = "queue-test"
        model.modelSelection.automaticModelSelection = false
        model.modelSelection.isConnected = true
        model.composer.queueMessages = true
    }

    func cleanUp() {
        model.stopGeneration()
        voiceTest.cleanUp()
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            preconditionFailure("Could not remove voice test history: \(error)")
        }
        for key in Self.defaultsKeys {
            if let value = defaults[key] { UserDefaults.standard.set(value, forKey: key.rawValue) }
            else { UserDefaults.standard.removeObject(forKey: key.rawValue) }
        }
    }

    func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        let settled = await condition()
        _ = try XCTUnwrap(settled ? true : nil, "Voice app state did not settle")
    }
}
