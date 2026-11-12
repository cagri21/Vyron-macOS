import Foundation

/// Virtual organization only. Project paths are references; these operations never move files.
public struct SidebarOrganization: Codable, Sendable, Equatable {
    private struct Placement: Codable, Sendable, Equatable {
        let item: SidebarItem
        var folderID: UUID
    }

    private let version: Int
    public private(set) var folders: [SidebarFolder]
    public private(set) var allProjects: [String]
    public private(set) var conversationIDs: [UUID]
    public private(set) var archivedConversationIDs: Set<UUID>
    public private(set) var pinnedItems: [SidebarItem]
    private var projectNames: [VyronSidebarProjectName]
    private var projectSources: [VyronSidebarProjectSources]
    private var placements: [Placement]
    private var expandedFolders: Set<UUID>
    private var expandedProjects: Set<String>

    public init() {
        version = 1
        folders = []
        allProjects = []
        conversationIDs = []
        archivedConversationIDs = []
        pinnedItems = []
        projectNames = []
        projectSources = []
        placements = []
        expandedFolders = []
        expandedProjects = []
    }

    public mutating func registerProject(path: String) throws {
        let path = try Self.projectPath(path)
        if !allProjects.contains(path) {
            allProjects.append(path)
            expandedProjects.insert(path)
        }
    }

    public mutating func registerConversation(id: UUID) {
        if !conversationIDs.contains(id) { conversationIDs.append(id) }
    }

    /// Changes the sidebar label only; the project's path and files retain their identity.
    public mutating func renameProject(path: String, name: String) throws {
        let path = try Self.projectPath(path)
        let name = try Self.projectName(name)
        try registerProject(path: path)
        projectNames.removeAll { $0.path == path }
        projectNames.append(VyronSidebarProjectName(path: path, name: name))
    }

    public func projectDisplayName(for path: String) -> String {
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        return projectNames.first { $0.path == path }?.name ?? URL(fileURLWithPath: path).lastPathComponent
    }

    /// Legacy projects retain their original folder until an explicit source-folder edit is saved.
    public func projectSourceFolders(for path: String) -> [String] {
        let path = URL(fileURLWithPath: path).standardizedFileURL.path
        return projectSources.first { $0.path == path }?.folders ?? [path]
    }

    /// Updates labels and source references atomically without moving files or changing project identity.
    public mutating func updateProject(path: String, name: String, sourceFolders: [String]) throws {
        let path = try Self.projectPath(path)
        let name = try Self.projectName(name)
        let folders = try VyronSidebarProjectSources.normalizedFolders(sourceFolders)
        try registerProject(path: path)
        projectNames.removeAll { $0.path == path }
        projectNames.append(VyronSidebarProjectName(path: path, name: name))
        projectSources.removeAll { $0.path == path }
        projectSources.append(VyronSidebarProjectSources(path: path, folders: folders))
    }

    /// Archiving preserves each chat's registration, folder, and pin for later restoration.
    public mutating func archiveConversations(ids: [UUID]) throws {
        let ids = Set(ids)
        guard ids.isSubset(of: Set(conversationIDs)) else {
            throw SidebarOrganizationError.invalidOrganization("An archived conversation is not registered.")
        }
        archivedConversationIDs.formUnion(ids)
    }

    public mutating func restoreConversation(id: UUID) {
        archivedConversationIDs.remove(id)
    }

    public func isConversationArchived(_ id: UUID) -> Bool {
        archivedConversationIDs.contains(id)
    }

    @discardableResult
    public mutating func createFolder(name: String, parentID: UUID? = nil) throws -> UUID {
        try requireFolder(parentID)
        let name = try Self.folderName(name)
        try requireUniqueName(name, parentID: parentID)
        let folder = SidebarFolder(name: name, parentID: parentID)
        folders.append(folder)
        expandedFolders.insert(folder.id)
        return folder.id
    }

    public mutating func renameFolder(id: UUID, name: String) throws {
        guard let index = folders.firstIndex(where: { $0.id == id }) else {
            throw SidebarOrganizationError.folderNotFound
        }
        let name = try Self.folderName(name)
        try requireUniqueName(name, parentID: folders[index].parentID, excluding: id)
        folders[index].rename(name)
    }

    public mutating func moveFolder(id: UUID, toParent parentID: UUID?) throws {
        guard let index = folders.firstIndex(where: { $0.id == id }) else {
            throw SidebarOrganizationError.folderNotFound
        }
        try requireFolder(parentID)
        guard !breadcrumb(for: parentID).contains(where: { $0.id == id }) else {
            throw SidebarOrganizationError.folderCycle
        }
        try requireUniqueName(folders[index].name, parentID: parentID, excluding: id)
        folders[index].reparent(parentID)
    }

    /// Children and items survive. Colliding child names gain a numeric suffix on reparenting.
    public mutating func removeFolder(id: UUID) throws {
        guard let folder = folders.first(where: { $0.id == id }) else { throw SidebarOrganizationError.folderNotFound }
        folders.removeAll { $0.id == id }
        expandedFolders.remove(id)
        for index in folders.indices where folders[index].parentID == id {
            let name = availableName(folders[index].name, parentID: folder.parentID, excluding: folders[index].id)
            folders[index].rename(name)
            folders[index].reparent(folder.parentID)
        }
        for index in placements.indices where placements[index].folderID == id {
            if let parent = folder.parentID { placements[index].folderID = parent }
        }
        if folder.parentID == nil { placements.removeAll { $0.folderID == id } }
    }

    public mutating func move(_ item: SidebarItem, to folderID: UUID?) throws {
        try requireFolder(folderID)
        let item = try register(item)
        placements.removeAll { $0.item == item }
        if let folderID { placements.append(Placement(item: item, folderID: folderID)) }
    }

    public mutating func togglePin(_ item: SidebarItem) throws {
        let item = try register(item)
        if pinnedItems.contains(item) { pinnedItems.removeAll { $0 == item } } else { pinnedItems.append(item) }
    }

    public mutating func removeItem(_ item: SidebarItem) {
        guard let item = try? Self.normalized(item) else { return }
        switch item {
        case .project(let path):
            allProjects.removeAll { $0 == path }
            expandedProjects.remove(path)
            projectNames.removeAll { $0.path == path }
            projectSources.removeAll { $0.path == path }
        case .conversation(let id):
            conversationIDs.removeAll { $0 == id }
            archivedConversationIDs.remove(id)
        }
        placements.removeAll { $0.item == item }
        pinnedItems.removeAll { $0 == item }
    }

    public mutating func setFolderExpanded(_ id: UUID, expanded: Bool) throws {
        try requireFolder(id)
        if expanded { expandedFolders.insert(id) } else { expandedFolders.remove(id) }
    }

    public mutating func setProjectExpanded(_ path: String, expanded: Bool) throws {
        try registerProject(path: path)
        let path = try Self.projectPath(path)
        if expanded { expandedProjects.insert(path) } else { expandedProjects.remove(path) }
    }

    public func folderID(for item: SidebarItem) -> UUID? {
        guard let item = try? Self.normalized(item) else { return nil }
        return placements.first { $0.item == item }?.folderID
    }

    public func isPinned(_ item: SidebarItem) -> Bool {
        guard let item = try? Self.normalized(item) else { return false }
        return pinnedItems.contains(item)
    }

    public func contains(_ item: SidebarItem) -> Bool {
        guard let item = try? Self.normalized(item) else { return false }
        switch item {
        case .project(let path): return allProjects.contains(path)
        case .conversation(let id): return conversationIDs.contains(id)
        }
    }

    public func folderChildren(of parentID: UUID?) -> [SidebarFolder] {
        folders.filter { $0.parentID == parentID }
    }

    /// Includes pinned items, allowing the caller to choose how to display its pinned section.
    public func items(in folderID: UUID?) -> [SidebarItem] {
        (allProjects.map(SidebarItem.project) + conversationIDs.map(SidebarItem.conversation)).filter {
            self.folderID(for: $0) == folderID
        }
    }

    public func breadcrumb(for folderID: UUID?) -> [SidebarFolder] {
        var result: [SidebarFolder] = []
        var current = folderID
        var seen: Set<UUID> = []
        while let id = current, seen.insert(id).inserted, let folder = folders.first(where: { $0.id == id }) {
            result.insert(folder, at: 0)
            current = folder.parentID
        }
        return result
    }

    public func isFolderExpanded(_ id: UUID) -> Bool { expandedFolders.contains(id) }

    public func isProjectExpanded(_ path: String) -> Bool {
        guard let path = try? Self.projectPath(path) else { return false }
        return expandedProjects.contains(path)
    }

    private mutating func register(_ item: SidebarItem) throws -> SidebarItem {
        let item = try Self.normalized(item)
        switch item {
        case .project(let path): try registerProject(path: path)
        case .conversation(let id): registerConversation(id: id)
        }
        return item
    }

    private static func normalized(_ item: SidebarItem) throws -> SidebarItem {
        switch item {
        case .project(let path): .project(try projectPath(path))
        case .conversation: item
        }
    }

    private static func projectPath(_ path: String) throws -> String {
        guard path.hasPrefix("/"), path.utf8.count <= 4_096,
            !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else {
            throw SidebarOrganizationError.invalidProjectPath
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func folderName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !name.isEmpty, name.count <= 80, name.utf8.count <= 320,
            !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw SidebarOrganizationError.invalidFolderName }
        return name
    }

    private static func projectName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !name.isEmpty, name.count <= 80, name.utf8.count <= 320,
            !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw SidebarOrganizationError.invalidProjectName }
        return name
    }

    private static func nameKey(_ name: String) -> String {
        name.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func requireFolder(_ id: UUID?) throws {
        if let id, !folders.contains(where: { $0.id == id }) { throw SidebarOrganizationError.folderNotFound }
    }

    private func requireUniqueName(_ name: String, parentID: UUID?, excluding id: UUID? = nil) throws {
        guard
            !folders.contains(where: {
                $0.id != id && $0.parentID == parentID && Self.nameKey($0.name) == Self.nameKey(name)
            })
        else { throw SidebarOrganizationError.duplicateFolderName }
    }

    private func availableName(_ name: String, parentID: UUID?, excluding id: UUID) -> String {
        if (try? requireUniqueName(name, parentID: parentID, excluding: id)) != nil { return name }
        var suffix = 2
        while true {
            let ending = " (\(suffix))"
            let candidate = String(name.prefix(80 - ending.count)) + ending
            if (try? requireUniqueName(candidate, parentID: parentID, excluding: id)) != nil { return candidate }
            suffix += 1
        }
    }

    func validate() throws {
        func require(_ valid: Bool, _ detail: String) throws {
            guard valid else { throw SidebarOrganizationError.invalidOrganization(detail) }
        }
        try require(version == 1, "The saved version is not supported.")
        let folderIDs = Set(folders.map(\.id))
        try require(folderIDs.count == folders.count, "Folder identifiers are duplicated.")
        for folder in folders {
            try require(try Self.folderName(folder.name) == folder.name, "A folder name is invalid.")
            try requireFolder(folder.parentID)
            try requireUniqueName(folder.name, parentID: folder.parentID, excluding: folder.id)
            var ancestors: Set<UUID> = [folder.id]
            var parent = folder.parentID
            while let id = parent {
                try require(ancestors.insert(id).inserted, "Folder nesting contains a cycle.")
                parent = folders.first { $0.id == id }?.parentID
            }
        }
        try require(Set(allProjects).count == allProjects.count, "Project references are duplicated.")
        for path in allProjects { try require(try Self.projectPath(path) == path, "A project path is invalid.") }
        try require(Set(projectNames.map(\.path)).count == projectNames.count, "Project labels are duplicated.")
        for label in projectNames {
            try require(allProjects.contains(label.path), "A project label has no registered project.")
            try require(try Self.projectName(label.name) == label.name, "A project label is invalid.")
        }
        try require(
            Set(projectSources.map(\.path)).count == projectSources.count,
            "Project source records are duplicated."
        )
        for sources in projectSources {
            try require(allProjects.contains(sources.path), "Project sources have no registered project.")
            try require(
                try VyronSidebarProjectSources.normalizedFolders(sources.folders) == sources.folders,
                "Project source folders are invalid."
            )
        }
        try require(Set(conversationIDs).count == conversationIDs.count, "Conversation identifiers are duplicated.")
        try require(
            archivedConversationIDs.isSubset(of: Set(conversationIDs)),
            "An archived conversation is not registered."
        )
        try require(
            Set(pinnedItems).count == pinnedItems.count
                && pinnedItems.allSatisfy { contains($0) && (try? Self.normalized($0)) == $0 },
            "A pinned item is invalid."
        )
        try require(Set(placements.map(\.item)).count == placements.count, "An item has multiple placements.")
        try require(
            placements.allSatisfy {
                contains($0.item) && (try? Self.normalized($0.item)) == $0.item && folderIDs.contains($0.folderID)
            },
            "An item placement is invalid."
        )
        try require(
            expandedFolders.isSubset(of: folderIDs) && expandedProjects.isSubset(of: Set(allProjects)),
            "An expanded item is invalid."
        )
    }

    private enum CodingKeys: String, CodingKey {
        case version, folders, allProjects, conversationIDs, pinnedItems, placements, expandedFolders, expandedProjects
        case projectNames, projectSources, archivedConversationIDs
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        folders = try values.decode([SidebarFolder].self, forKey: .folders)
        allProjects = try values.decode([String].self, forKey: .allProjects)
        conversationIDs = try values.decode([UUID].self, forKey: .conversationIDs)
        archivedConversationIDs = try values.decodeIfPresent(Set<UUID>.self, forKey: .archivedConversationIDs) ?? []
        pinnedItems = try values.decode([SidebarItem].self, forKey: .pinnedItems)
        projectNames = try values.decodeIfPresent([VyronSidebarProjectName].self, forKey: .projectNames) ?? []
        projectSources = try values.decodeIfPresent([VyronSidebarProjectSources].self, forKey: .projectSources) ?? []
        placements = try values.decode([Placement].self, forKey: .placements)
        expandedFolders = try values.decode(Set<UUID>.self, forKey: .expandedFolders)
        expandedProjects = try values.decode(Set<String>.self, forKey: .expandedProjects)
        do { try validate() } catch {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: error.localizedDescription)
            )
        }
    }
}
