import Foundation
import VyronCore

extension AppModel {
    func loadSidebarOrganization() {
        do {
            let saved = try sidebarState.sidebarStore.load()
            var organization = saved ?? migratedSidebarOrganization()
            let original = organization
            // Only explicit chat deletion removes references, so recovered history
            // can regain its folder and pin assignments after a read failure.
            for conversation in conversations { organization.registerConversation(id: conversation.id) }
            if saved == nil || organization != original { try sidebarState.sidebarStore.save(organization) }
            sidebarState.sidebarOrganization = organization
        } catch {
            sidebarState.sidebarOrganization = migratedSidebarOrganization()
            reportSidebarError(error.localizedDescription)
        }
    }

    private func migratedSidebarOrganization() -> SidebarOrganization {
        var organization = SidebarOrganization()
        let paths = workspaceState.recentWorkspacePaths + conversations.compactMap(\.sidebarProjectPath)
        for path in paths {
            do { try organization.registerProject(path: path) }
            catch { reportSidebarError(error.localizedDescription) }
        }
        let savedOwner = workspaceState.savedSelectedProjectPath
        for path in organization.allProjects {
            var sources: [String] = []
            if savedOwner == path, let currentSource = workspaceState.workspaceURL?.standardizedFileURL.path {
                sources.append(currentSource)
            }
            for conversation in conversations {
                guard conversation.sidebarProjectPath.map({ URL(fileURLWithPath: $0).standardizedFileURL.path }) == path,
                    let source = conversation.workspacePath else { continue }
                let normalized = URL(fileURLWithPath: source).standardizedFileURL.path
                if !sources.contains(normalized) { sources.append(normalized) }
            }
            guard !sources.isEmpty else { continue }
            do {
                try organization.updateProject(
                    path: path,
                    name: organization.projectDisplayName(for: path),
                    sourceFolders: Array(sources.prefix(VyronSidebarProjectSources.maximumFolderCount))
                )
            } catch { reportSidebarError(error.localizedDescription) }
        }
        if let source = workspaceState.workspaceURL?.standardizedFileURL.path,
            !organization.allProjects.contains(where: { organization.projectSourceFolders(for: $0).contains(source) }) {
            do { try organization.registerProject(path: source) }
            catch { reportSidebarError(error.localizedDescription) }
        }
        for conversation in conversations { organization.registerConversation(id: conversation.id) }
        return organization
    }

    func sidebarProjects(in folderID: UUID?) -> [String] {
        let organization = sidebarState.sidebarOrganization
        return organization.allProjects.filter {
            let item = SidebarItem.project($0)
            return !organization.isPinned(item) && organization.folderID(for: item) == folderID
        }
    }

    func sidebarChats(in folderID: UUID?) -> [Conversation] {
        let organization = sidebarState.sidebarOrganization
        let projects = Set(organization.allProjects)
        return conversations.filter { conversation in
            let item = SidebarItem.conversation(conversation.id)
            guard !organization.isConversationArchived(conversation.id),
                !organization.isPinned(item), organization.folderID(for: item) == folderID
            else {
                return false
            }
            if folderID != nil { return true }
            guard let path = conversation.sidebarProjectPath else { return true }
            return !projects.contains(URL(fileURLWithPath: path).standardizedFileURL.path)
        }
    }

    func sidebarProjectChats(_ path: String) -> [Conversation] {
        let projectPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let organization = sidebarState.sidebarOrganization
        return conversations.filter { conversation in
            guard !organization.isConversationArchived(conversation.id),
                let workspacePath = conversation.sidebarProjectPath,
                URL(fileURLWithPath: workspacePath).standardizedFileURL.path == projectPath
            else { return false }
            let item = SidebarItem.conversation(conversation.id)
            return !organization.isPinned(item) && organization.folderID(for: item) == nil
        }
    }

    func sidebarConversation(_ id: UUID) -> Conversation? {
        guard !sidebarState.sidebarOrganization.isConversationArchived(id) else { return nil }
        return conversations.first { $0.id == id }
    }

    func sidebarFolderMoveTargets(excluding id: UUID) -> [SidebarFolder] {
        sidebarState.sidebarOrganization.folders.filter { folder in
            !sidebarState.sidebarOrganization.breadcrumb(for: folder.id).contains { $0.id == id }
        }
    }

    @discardableResult
    func createSidebarFolder(name: String, parentID: UUID? = nil) -> UUID? {
        var createdID: UUID?
        let saved = changeSidebar { organization in
            createdID = try organization.createFolder(name: name, parentID: parentID)
            try Self.expandSidebarAncestors(parentID, in: &organization)
        }
        return saved ? createdID : nil
    }

    @discardableResult
    func renameSidebarFolder(_ id: UUID, name: String) -> Bool {
        changeSidebar { try $0.renameFolder(id: id, name: name) }
    }

    @discardableResult
    func moveSidebarFolder(_ id: UUID, toParent parentID: UUID?) -> Bool {
        changeSidebar { organization in
            try organization.moveFolder(id: id, toParent: parentID)
            try Self.expandSidebarAncestors(parentID, in: &organization)
        }
    }

    @discardableResult
    func removeSidebarFolder(_ id: UUID) -> Bool {
        changeSidebar { try $0.removeFolder(id: id) }
    }

    @discardableResult
    func moveSidebarItem(_ item: SidebarItem, toFolder folderID: UUID?) -> Bool {
        changeSidebar { organization in
            try organization.move(item, to: folderID)
            try Self.expandSidebarAncestors(folderID, in: &organization)
        }
    }

    func toggleSidebarPin(_ item: SidebarItem) {
        changeSidebar { organization in
            try organization.togglePin(item)
            if !organization.isPinned(item) {
                try Self.expandSidebarAncestors(organization.folderID(for: item), in: &organization)
            }
        }
    }

    func setSidebarFolderExpanded(_ id: UUID, expanded: Bool) {
        changeSidebar { try $0.setFolderExpanded(id, expanded: expanded) }
    }

    func setSidebarProjectExpanded(_ path: String, expanded: Bool) {
        changeSidebar { try $0.setProjectExpanded(path, expanded: expanded) }
    }

    @discardableResult
    func renameConversation(_ id: UUID, title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 120,
            !title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
            let index = conversations.firstIndex(where: { $0.id == id })
        else {
            reportSidebarError(VyronGeneralText.invalidChatName)
            return false
        }
        let previous = conversations[index].title
        conversations[index].title = title
        guard saveRenamedSidebarConversation() else {
            conversations[index].title = previous
            return false
        }
        clearSidebarError()
        return true
    }

    func registerSidebarProject(_ path: String) {
        guard !sidebarState.sidebarOrganization.contains(.project(path)) else { return }
        changeSidebar { try $0.registerProject(path: path) }
    }

    func registerSidebarConversation(_ id: UUID) {
        changeSidebar { organization in
            organization.registerConversation(id: id)
            if let path = conversations.first(where: { $0.id == id })?.sidebarProjectPath {
                if !organization.contains(.project(path)),
                    let source = conversations.first(where: { $0.id == id })?.workspacePath {
                    try organization.updateProject(
                        path: path,
                        name: URL(fileURLWithPath: path).lastPathComponent,
                        sourceFolders: [source]
                    )
                }
                try organization.setProjectExpanded(path, expanded: true)
                try Self.expandSidebarAncestors(organization.folderID(for: .project(path)), in: &organization)
            }
        }
    }

    func removeSidebarConversation(_ id: UUID) {
        changeSidebar { $0.removeItem(.conversation(id)) }
    }

    @discardableResult
    func changeSidebar(_ change: (inout SidebarOrganization) throws -> Void) -> Bool {
        do {
            var updated = sidebarState.sidebarOrganization
            try change(&updated)
            if updated != sidebarState.sidebarOrganization { try sidebarState.sidebarStore.save(updated) }
            sidebarState.sidebarOrganization = updated
            clearSidebarError()
            return true
        } catch SidebarOrganizationError.invalidProjectName {
            reportSidebarError(VyronSidebarText.invalidProjectName)
            return false
        } catch SidebarOrganizationError.invalidSourceFolders {
            reportSidebarError(VyronSidebarText.invalidSourceFolders)
            return false
        } catch {
            reportSidebarError(error.localizedDescription)
            return false
        }
    }

    private static func expandSidebarAncestors(_ folderID: UUID?, in organization: inout SidebarOrganization) throws {
        for folder in organization.breadcrumb(for: folderID) {
            try organization.setFolderExpanded(folder.id, expanded: true)
        }
    }

    private func reportSidebarError(_ message: String) {
        sidebarState.lastSidebarError = message
        errorMessage = message
    }

    private func clearSidebarError() {
        if let lastSidebarError = sidebarState.lastSidebarError, errorMessage == lastSidebarError { errorMessage = nil }
        sidebarState.lastSidebarError = nil
    }
}
