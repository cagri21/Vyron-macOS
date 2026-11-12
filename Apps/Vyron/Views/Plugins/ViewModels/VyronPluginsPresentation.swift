import Combine
import Foundation
import VyronCore

@MainActor
final class VyronPluginsPresentation: ObservableObject {
    @Published private(set) var section = VyronCustomizeSection.plugins
    @Published var searchQuery = ""
    @Published var filter = VyronPluginFilter.all
    @Published private(set) var selectedConnectionID: UUID?
    @Published var editingProfile: MCPConnectionProfile?
    @Published var removingProfile: MCPConnectionProfile?
    @Published private(set) var catalogError: String?

    func showAll() {
        section = .plugins
        catalogError = nil
        selectedConnectionID = nil
        filter = .all
        searchQuery = ""
    }

    func select(_ connectionID: UUID) {
        section = .plugins
        catalogError = nil
        selectedConnectionID = connectionID
    }

    func showSearchResults() {
        selectedConnectionID = nil
    }

    func showSkills() {
        section = .skills
    }

    func addConnection() {
        catalogError = nil
        editingProfile = MCPConnectionProfile(name: "")
    }

    func addPenpot() {
        catalogError = nil
        editingProfile = .penpot
    }

    func addCodexCatalog(scriptURL: URL? = VyronCodexCatalogPreset.bundledScriptURL) {
        guard let profile = VyronCodexCatalogPreset.makeProfile(scriptURL: scriptURL) else {
            catalogError = VyronPluginText.codexUnavailable
            return
        }
        catalogError = nil
        editingProfile = profile
    }

    func addAgentCatalog(
        projectDirectory: URL? = nil,
        scriptURL: URL? = VyronAgentCatalogPreset.bundledScriptURL
    ) {
        guard let profile = VyronAgentCatalogPreset.makeProfile(
            scriptURL: scriptURL,
            projectDirectory: projectDirectory
        ) else {
            catalogError = VyronPluginText.agentBridgeUnavailable
            return
        }
        catalogError = nil
        editingProfile = profile
    }

    func visibleProfiles(
        _ profiles: [MCPConnectionProfile],
        connectedIDs: Set<UUID>
    ) -> [MCPConnectionProfile] {
        profiles.filter { profile in
            (filter != .connected || connectedIDs.contains(profile.id))
                && matchesSearch(profile.name, detail: VyronPluginItem(profile: profile).address)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func matchesSearch(_ name: String, detail: String) -> Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || name.localizedStandardContains(query) || detail.localizedStandardContains(query)
    }

    func reconcileSelection(with profiles: [MCPConnectionProfile]) {
        guard let selectedConnectionID, !profiles.contains(where: { $0.id == selectedConnectionID }) else { return }
        self.selectedConnectionID = nil
    }
}
