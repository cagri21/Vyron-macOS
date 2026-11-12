import Combine
import Foundation
import VyronCore

@MainActor
final class VyronSkillsPresentation: ObservableObject {
    @Published var searchQuery = ""
    @Published var filter = VyronSkillFilter.all
    @Published private(set) var inventory: VyronSkillInventory?
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadError = false
    @Published private(set) var selectedSkillID: String?
    @Published private(set) var refreshID = UUID()

    private let homeDirectory: URL
    private let loader: @Sendable ([VyronSkillRoot]) async throws -> VyronSkillInventory
    private var installationObservation: AnyCancellable?
    private var activeLoadID: UUID?
    private var loadedProjectDirectory: URL?
    private var hasLoaded = false

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        loader: @escaping @Sendable ([VyronSkillRoot]) async throws -> VyronSkillInventory = { roots in
            try await VyronSkillsPresentation.discover(roots: roots)
        }
    ) {
        self.homeDirectory = homeDirectory
        self.loader = loader
        installationObservation = NotificationCenter.default.publisher(for: VyronSkillSetupNotifications.didInstall)
            .sink { [weak self] _ in self?.refresh() }
    }

    var selectedSkill: VyronLocalSkill? {
        inventory?.skills.first { $0.id == selectedSkillID }
    }

    var visibleSkills: [VyronLocalSkill] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return (inventory?.skills ?? []).filter { skill in
            filter.includes(skill.source) && (
                query.isEmpty
                    || skill.name.localizedStandardContains(query)
                    || skill.description.localizedStandardContains(query)
                    || skill.fileURL.path.localizedStandardContains(query)
            )
        }.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }

    func roots(projectDirectory: URL?) -> [VyronSkillRoot] {
        var seen = Set<URL>()
        return VyronSkillRoot.local(homeDirectory: homeDirectory, projectDirectory: projectDirectory)
            .filter { seen.insert($0.directoryURL).inserted }
    }

    func load(projectDirectory: URL?) async {
        let requestID = UUID()
        activeLoadID = requestID
        isLoading = true
        hasLoadError = false
        if !hasLoaded || projectDirectory != loadedProjectDirectory {
            inventory = nil
            selectedSkillID = nil
        }
        defer {
            if activeLoadID == requestID { isLoading = false }
        }
        do {
            let result = try await loader(roots(projectDirectory: projectDirectory))
            guard !Task.isCancelled, activeLoadID == requestID else { return }
            inventory = result
            loadedProjectDirectory = projectDirectory
            hasLoaded = true
            if !result.skills.contains(where: { $0.id == selectedSkillID }) { selectedSkillID = nil }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, activeLoadID == requestID else { return }
            hasLoadError = true
        }
    }

    func refresh() {
        refreshID = UUID()
    }

    func select(_ skill: VyronLocalSkill) {
        selectedSkillID = skill.id
    }

    func showList() {
        selectedSkillID = nil
    }

    func showAll() {
        selectedSkillID = nil
        filter = .all
        searchQuery = ""
    }

    private nonisolated static func discover(roots: [VyronSkillRoot]) async throws -> VyronSkillInventory {
        let task = Task.detached(priority: .userInitiated) {
            try VyronSkillDiscovery().discover(in: roots)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
