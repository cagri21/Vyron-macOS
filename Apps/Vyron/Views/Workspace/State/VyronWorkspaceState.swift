import Combine
import Foundation
import VyronCore
import VyronDevelopment

@MainActor
final class VyronWorkspaceState: ObservableObject {
    @Published var workspaceURL: URL?
    @Published var selectedProjectPath: String? {
        didSet {
            defaults.set(selectedProjectPath, forKey: VyronUserDefaultsKey.selectedSidebarProjectPath.rawValue)
        }
    }
    @Published var workspaceFiles: [WorkspaceFile] = []
    @Published var isLoadingWorkspace = false
    @Published var searchText = ""
    @Published var recentWorkspacePaths: [String]

    var workspace: ProjectWorkspace?
    var developmentWorkspace: DevelopmentWorkspace?
    var developmentWorkspaces: [String: DevelopmentWorkspace] = [:]
    var workspaceOpeningError: String?
    var projectSetupError: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recentWorkspacePaths = defaults.stringArray(forKey: VyronUserDefaultsKey.recentWorkspacePaths.rawValue) ?? []
    }

    var savedSelectedProjectPath: String? {
        defaults.string(forKey: VyronUserDefaultsKey.selectedSidebarProjectPath.rawValue)
    }

    var filteredFiles: [WorkspaceFile] {
        guard !searchText.isEmpty else { return workspaceFiles }
        return workspaceFiles.filter { $0.path.localizedCaseInsensitiveContains(searchText) }
    }

    func restoreWorkspaceLocation() {
        if let path = defaults.string(forKey: VyronUserDefaultsKey.workspacePath.rawValue) {
            workspaceURL = URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    func saveWorkspaceLocation(_ path: String) {
        defaults.set(path, forKey: VyronUserDefaultsKey.workspacePath.rawValue)
    }

    func clearWorkspaceLocation() {
        defaults.removeObject(forKey: VyronUserDefaultsKey.workspacePath.rawValue)
    }

    func saveRecentWorkspacePaths() {
        defaults.set(recentWorkspacePaths, forKey: VyronUserDefaultsKey.recentWorkspacePaths.rawValue)
    }

    func recordRecentWorkspace(_ path: String) {
        recentWorkspacePaths.removeAll { $0 == path }
        recentWorkspacePaths.insert(path, at: 0)
        recentWorkspacePaths = Array(recentWorkspacePaths.prefix(8))
        saveRecentWorkspacePaths()
    }
}
