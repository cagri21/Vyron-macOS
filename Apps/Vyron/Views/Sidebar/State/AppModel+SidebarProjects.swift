import AppKit
import Foundation
import VyronCore

extension AppModel {
    var archivedSidebarConversations: [Conversation] {
        conversations.filter { sidebarState.sidebarOrganization.isConversationArchived($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func sidebarProjectName(_ path: String) -> String {
        sidebarState.sidebarOrganization.projectDisplayName(for: path)
    }

    func sidebarProjectConversations(_ path: String) -> [Conversation] {
        let projectPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return conversations.filter { conversation in
            conversation.sidebarProjectPath.map {
                URL(fileURLWithPath: $0).standardizedFileURL.path == projectPath
            } == true
        }
    }

    func isSidebarConversationActive(_ id: UUID) -> Bool {
        if isSideChatGenerating(id) { return true }
        if foregroundRun.response(in: id) != nil { return true }
        if computerWork.pendingAgentGoal?.conversationID == id { return true }
        if selectedConversationID == id, computerWork.isComputerWorkActive { return true }
        if foregroundRun.isStoppingDevelopment, foregroundRun.stoppingDevelopmentConversationID == id { return true }
        guard let taskID = scheduledTasks.activeTaskID else { return false }
        return scheduledTasks.tasks.first { $0.id == taskID }?.progress.lastRun?.output.conversationID == id
    }

    func sidebarProjectActiveChatCount(_ path: String) -> Int {
        sidebarProjectConversations(path).filter { isSidebarConversationActive($0.id) }.count
    }

    func canArchiveSidebarProject(_ path: String) -> Bool {
        canRemoveSidebarProject(path)
            && sidebarProjectConversations(path).contains {
                !sidebarState.sidebarOrganization.isConversationArchived($0.id)
            }
    }

    func canRemoveSidebarProject(_ path: String) -> Bool {
        !isShuttingDown && sidebarProjectActiveChatCount(path) == 0
            && !(sidebarActiveProjectPath == URL(fileURLWithPath: path).standardizedFileURL.path
                && (foregroundRun.isGenerating || computerWork.isComputerWorkActive || foregroundRun.isStoppingDevelopment || isRunningScheduledTask))
    }

    @discardableResult
    func renameSidebarProject(_ path: String, name: String) -> Bool {
        changeSidebar { try $0.renameProject(path: path, name: name) }
    }

    func newSidebarProjectConversation(_ path: String) {
        newConversation()
        sidebarState.sidebarSearchText = ""
        openRecentProject(path)
        setSidebarProjectExpanded(path, expanded: true)
    }

    func revealSidebarProject(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting(
            sidebarProjectSourceFolders(path).map { URL(fileURLWithPath: $0, isDirectory: true) }
        )
    }

    @discardableResult
    func archiveSidebarProject(_ path: String) -> Bool {
        guard canArchiveSidebarProject(path) else {
            errorMessage = canRemoveSidebarProject(path)
                ? VyronSidebarText.archiveUnavailable : VyronSidebarText.projectBusy
            return false
        }
        let ids = sidebarProjectConversations(path).map(\.id)
        guard changeSidebar({ try $0.archiveConversations(ids: ids) }) else { return false }
        if let selectedConversationID, ids.contains(selectedConversationID) { newConversation() }
        return true
    }

    @discardableResult
    func restoreSidebarConversation(_ id: UUID) -> Bool {
        guard let conversation = conversations.first(where: { $0.id == id }) else { return false }
        return changeSidebar { organization in
            organization.restoreConversation(id: id)
            let displayGroup = organization.chatDisplayGroup(id)
            if case .project(let project)? = displayGroup {
                try Self.expandSidebarProject(project.path, in: &organization)
            } else if displayGroup == nil, let path = conversation.sidebarProjectPath,
                organization.contains(.project(path)) {
                try Self.expandSidebarProject(path, in: &organization)
            }
            try Self.expandSidebarAncestors(organization.folderID(for: .conversation(id)), in: &organization)
        }
    }

    @discardableResult
    func removeSidebarProject(_ path: String) -> Bool {
        guard canRemoveSidebarProject(path) else {
            errorMessage = VyronSidebarText.removeProjectUnavailable
            return false
        }
        let projectURL = URL(fileURLWithPath: path).standardizedFileURL
        let removesCurrentProject = sidebarActiveProjectPath == projectURL.path
        guard changeSidebar({ $0.removeItem(.project(projectURL.path)) }) else { return false }
        workspaceState.recentWorkspacePaths.removeAll { URL(fileURLWithPath: $0).standardizedFileURL == projectURL }
        workspaceState.saveRecentWorkspacePaths()
        if removesCurrentProject {
            newConversation()
            clearWorkspace()
        }
        return true
    }
}
