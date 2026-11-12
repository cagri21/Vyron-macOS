import Foundation
import VyronCore
import VyronDevelopment

extension AppModel {
    /// Applies a confirmed project move to the active conversation and generation.
    func adoptCreatedProject(
        _ development: DevelopmentWorkspace,
        generationID: UUID,
        conversationID: UUID,
        destination: VyronChatHandoffSelection? = nil
    ) async throws {
        let owner = try createdProjectOwner(generationID: generationID, conversationID: conversationID)
        let project = try ProjectWorkspace(rootURL: development.rootURL)
        let files = try await project.files(limit: VyronWorkspaceLimits.maximumInventoryFiles)
        let developmentFiles = try await development.listFiles(limit: VyronWorkspaceInspectorLimits.maximumListedFiles)
        let changes = await development.changes()
        guard ownsInteractiveWorkResponse(owner), !isRunningScheduledTask,
            let index = conversations.firstIndex(where: { $0.id == conversationID }) else {
            throw CancellationError()
        }
        let url = development.rootURL
        let folder = VyronFolderCreationRequest(path: url.path, projectURL: url)
        guard try VyronFolderCreation.existingDestination(for: folder) == url else {
            throw DevelopmentError(VyronHandoffText.unavailable)
        }
        let originalConversation = conversations[index]
        let projectPath = try conversationMoveProjectPath(
            for: url.path, destination: destination, currentProjectPath: originalConversation.sidebarProjectPath
        )
        let previousOrganization = sidebarState.sidebarOrganization
        if projectPath == url.path, !changeSidebar({ organization in
            if !organization.contains(.project(url.path)) {
                try organization.updateProject(path: url.path, name: url.lastPathComponent, sourceFolders: [url.path])
            } else {
                let sources = organization.projectSourceFolders(for: url.path)
                if !sources.contains(url.path) {
                    try organization.updateProject(
                        path: url.path, name: organization.projectDisplayName(for: url.path),
                        sourceFolders: sources + [url.path]
                    )
                }
            }
        }) { throw DevelopmentError(VyronFolderText.saveFailed) }
        conversations[index].workspacePath = url.path
        conversations[index].projectPath = projectPath
        guard saveHistory() else {
            conversations[index] = originalConversation
            changeSidebar { $0 = previousOrganization }
            throw DevelopmentError(VyronFolderText.saveFailed)
        }
        workspaceState.developmentWorkspaces[url.path] = development
        guard selectedConversationID == conversationID else { return }
        setCreatedProjectWorkspace(project, development: development)
        workspaceState.workspaceURL = url
        workspaceState.selectedProjectPath = projectPath
        workspaceState.workspaceFiles = files
        inspector.developmentFiles = developmentFiles
        inspector.developmentChanges = changes
        inspector.selectedProjectFilePath = nil
        inspector.projectFilePreview = ""
        inspector.selectedChangePath = changes.first?.path
        composerAttachments.attachedFiles = []
        workspaceState.saveWorkspaceLocation(url.path)
        workspaceState.recordRecentWorkspace(projectPath)
    }

    private func conversationMoveProjectPath(
        for folder: String, destination: VyronChatHandoffSelection?, currentProjectPath: String?
    ) throws -> String {
        if let destination, destination.workspacePath == folder {
            guard sidebarState.sidebarOrganization.contains(.project(destination.projectPath)),
                sidebarProjectSourceFolders(destination.projectPath).contains(folder) else {
                throw DevelopmentError(VyronHandoffText.unavailable)
            }
            return destination.projectPath
        }
        if sidebarState.sidebarOrganization.contains(.project(folder)) { return folder }
        let owners = sidebarState.sidebarOrganization.allProjects.filter {
            sidebarProjectSourceFolders($0).contains(folder)
        }
        if let currentProjectPath, owners.contains(currentProjectPath) { return currentProjectPath }
        return owners.count == 1 ? owners[0] : folder
    }

    private func createdProjectOwner(generationID: UUID, conversationID: UUID) throws -> VyronResponseIdentity {
        try Task.checkCancellation()
        guard !isRunningScheduledTask, let response = foregroundRun.response(forGeneration: generationID),
            response.conversationID == conversationID, ownsInteractiveWorkResponse(response)
        else { throw CancellationError() }
        return response
    }
}
