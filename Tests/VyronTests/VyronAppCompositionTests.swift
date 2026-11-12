import Foundation
import VyronCore
import XCTest
@testable import Vyron

@MainActor
final class VyronAppCompositionTests: XCTestCase {
    func testInjectedPreferencesRestoreSidebarOwnershipAndFeatureSettings() throws {
        let paths = makeStoragePaths()
        let suite = "VyronAppCompositionTests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let owner = paths.directory.appendingPathComponent("Project").path
        let source = paths.directory.appendingPathComponent("Source").path
        preferences.set([owner], forKey: VyronUserDefaultsKey.recentWorkspacePaths.rawValue)
        preferences.set(owner, forKey: VyronUserDefaultsKey.selectedSidebarProjectPath.rawValue)
        preferences.set(source, forKey: VyronUserDefaultsKey.workspacePath.rawValue)
        preferences.set("local-coder:test", forKey: VyronUserDefaultsKey.selectedLocalModel.rawValue)
        preferences.set(["download:test"], forKey: VyronUserDefaultsKey.pausedModelDownloads.rawValue)
        preferences.set(
            VyronProjectApprovalMode.askForApproval.rawValue,
            forKey: VyronUserDefaultsKey.projectCommandApprovalMode.rawValue
        )
        let queueKey = VyronUserDefaultsKey.queueFollowUpMessages.rawValue
        let originalQueuePreference = UserDefaults.standard.object(forKey: queueKey) as? Bool
        let injectedQueuePreference = !(originalQueuePreference ?? true)
        preferences.set(injectedQueuePreference, forKey: queueKey)

        let model = AppModel(storagePaths: paths, preferences: preferences)

        XCTAssertEqual(model.workspaceState.selectedProjectPath, owner)
        XCTAssertEqual(model.sidebarState.sidebarOrganization.allProjects, [owner])
        XCTAssertEqual(model.sidebarProjectSourceFolders(owner), [source])
        XCTAssertEqual(model.modelSelection.selectedModel, "local-coder:test")
        XCTAssertEqual(model.modelDownloads.pausedTags, ["download:test"])
        XCTAssertEqual(model.interactions.projectApprovalMode, .askForApproval)
        XCTAssertEqual(model.composer.queueMessages, injectedQueuePreference)
        model.composer.queueMessages.toggle()
        XCTAssertEqual(preferences.bool(forKey: queueKey), !injectedQueuePreference)
        XCTAssertEqual(UserDefaults.standard.object(forKey: queueKey) as? Bool, originalQueuePreference)
    }

    func testOpensExistingConversationAndConnectionFilesInAnOverriddenRoot() throws {
        let paths = makeStoragePaths()
        let suite = "VyronAppCompositionTests.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let profile = ModelConnectionProfile(
            name: "Saved server",
            kind: .openAICompatible,
            endpoint: "https://models.example.invalid/v1",
            selectedModel: "saved-model"
        )
        let saved = ModelConnectionState(profiles: [profile], activeConnectionID: profile.id)
        let connectionsURL = paths.directory.appendingPathComponent("model-connections.json")
        try ModelConnectionStore(fileURL: connectionsURL).save(saved)
        let conversation = Conversation(title: "Saved conversation", workspacePath: nil)
        let historyURL = paths.directory.appendingPathComponent("conversations.json")
        try JSONEncoder().encode([conversation]).write(to: historyURL)

        let model = AppModel(storagePaths: paths, preferences: preferences)

        XCTAssertEqual(model.conversations.map(\.id), [conversation.id])
        XCTAssertEqual(model.modelSelection.activeConnectionID, profile.id)
        XCTAssertEqual(model.modelSelection.selectedModel, "saved-model")
        XCTAssertEqual(try ModelConnectionStore(fileURL: connectionsURL).load(), saved)
        XCTAssertEqual(paths.url(for: .localAuthentication).path, paths.directory.path + "/LocalAuth")
    }

    func testLiveStorageUsesTheExistingApplicationSupportLocation() throws {
        let support = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        let paths = VyronAppStoragePaths.applicationSupport

        XCTAssertEqual(paths.directory.path, support.appendingPathComponent("VyronAI").path)
    }

    private func makeStoragePaths() -> VyronAppStoragePaths {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronAppCompositionTests-\(UUID())", isDirectory: true)
            .standardizedFileURL
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        return VyronAppStoragePaths(directory: directory)
    }
}
