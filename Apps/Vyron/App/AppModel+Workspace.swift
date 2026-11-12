import AppKit
import Foundation
import VyronCore
import VyronDevelopment

extension AppModel {
    var chatSchedulingWorkspaceMatches: Bool { selectedProjectBindingMatches }

    var selectedProjectBindingMatches: Bool {
        guard let project = workspaceState.developmentWorkspace, let workspaceURL = workspaceState.workspaceURL,
            project.rootURL == workspaceURL
        else { return false }
        guard let selectedConversation else { return true }
        guard let path = selectedConversation.workspacePath else { return false }
        return URL(fileURLWithPath: path).standardizedFileURL == workspaceURL.standardizedFileURL
            && selectedConversation.sidebarProjectPath == sidebarActiveProjectPath
            && selectedProjectSourceFolderIsAttached
    }

    func setCreatedProjectWorkspace(_ project: ProjectWorkspace, development: DevelopmentWorkspace) {
        workspaceState.workspace = project
        workspaceState.developmentWorkspace = development
        inspector.projectPreviewID = UUID()
        composerAttachments.generation = UUID()
        composerAttachments.pendingAttachments = []
    }

    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.title = VyronStatusText.chooseWorkspace
        panel.message =
            VyronStatusText.chooseWorkspaceHint
        panel.prompt = VyronWorkspaceText.openProject
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if workspaceState.workspaceURL?.standardizedFileURL == url.standardizedFileURL,
                workspaceState.developmentWorkspace != nil {
                return
            }
            newConversation()
            let selectionID = prepareWorkspaceSelection(url)
            Task {
                await loadAddedWorkspace(url, expectedSelectionID: selectionID)
            }
        }
    }

    func loadWorkspace(
        _ url: URL,
        expectedConversationID: UUID? = nil,
        expectedSelectionID: UUID? = nil,
        projectPath: String? = nil
    ) async {
        // A canceled handoff can still use this path to restore its previous workspace.
        guard !isShuttingDown else { return }
        if let expectedConversationID, selectedConversationID != expectedConversationID { return }
        if let expectedSelectionID, composerAttachments.generation != expectedSelectionID { return }
        if !foregroundRun.canContinueInBackground { stopGeneration() }
        let ownerPath = projectPath ?? url.standardizedFileURL.path
        prepareWorkspaceSelection(url, projectPath: ownerPath)
        let generation = UUID()
        composerAttachments.generation = generation
        workspaceState.isLoadingWorkspace = true
        defer { if composerAttachments.generation == generation { workspaceState.isLoadingWorkspace = false } }
        composerAttachments.pendingAttachments = []
        do {
            let newWorkspace = try ProjectWorkspace(rootURL: url)
            if sidebarState.sidebarOrganization.contains(.project(ownerPath)),
                !sidebarProjectSourceFolders(ownerPath).contains(newWorkspace.rootURL.path) {
                throw DevelopmentError(VyronSidebarText.sourceFolderRemoved)
            }
            let files = try await newWorkspace.files(limit: VyronWorkspaceLimits.maximumInventoryFiles)
            guard !isShuttingDown, composerAttachments.generation == generation else { return }
            let canonicalURL = newWorkspace.rootURL
            let development: DevelopmentWorkspace
            if let existing = workspaceState.developmentWorkspaces[canonicalURL.path] {
                development = existing
            } else {
                development = try DevelopmentWorkspace(rootURL: canonicalURL)
            }
            let projectFiles = try await development.listFiles(limit: VyronWorkspaceInspectorLimits.maximumListedFiles)
            let changes = await development.changes()
            guard !isShuttingDown, composerAttachments.generation == generation else { return }
            if let expectedConversationID, selectedConversationID != expectedConversationID { return }
            workspaceState.workspace = newWorkspace
            workspaceState.workspaceURL = canonicalURL
            let hasExistingIdentity = sidebarState.sidebarOrganization.contains(.project(ownerPath))
                || (projectPath != nil && ownerPath != url.standardizedFileURL.path)
            let identityPath = hasExistingIdentity
                ? URL(fileURLWithPath: ownerPath).standardizedFileURL.path : canonicalURL.path
            workspaceState.selectedProjectPath = identityPath
            workspaceState.workspaceFiles = files
            workspaceState.developmentWorkspace = development
            workspaceState.developmentWorkspaces[canonicalURL.path] = development
            inspector.developmentFiles = projectFiles
            inspector.developmentChanges = changes
            inspector.selectedProjectFilePath = nil
            inspector.projectPreviewID = UUID()
            inspector.projectFilePreview = ""
            inspector.selectedChangePath = changes.first?.path
            composerAttachments.attachedFiles = []
            workspaceState.saveWorkspaceLocation(canonicalURL.path)
            workspaceState.recordRecentWorkspace(identityPath)
            statusMessage = nil
            if errorMessage == workspaceState.workspaceOpeningError { errorMessage = nil }
            workspaceState.workspaceOpeningError = nil
            registerLoadedSidebarProject(identityPath, sourceFolder: canonicalURL.path)
            if let expectedConversationID,
                let index = conversations.firstIndex(where: { $0.id == expectedConversationID }),
                conversations[index].workspacePath != canonicalURL.path
                    || conversations[index].sidebarProjectPath != identityPath {
                conversations[index].workspacePath = canonicalURL.path
                conversations[index].projectPath = identityPath
                saveHistory()
            }
        } catch {
            guard !isShuttingDown, composerAttachments.generation == generation else { return }
            let message = VyronStatusText.workspaceOpenFailure(error.localizedDescription)
            workspaceState.workspaceOpeningError = message
            errorMessage = message
            statusMessage = VyronStatusText.projectUnavailable
        }
    }

    func clearWorkspace() {
        if !foregroundRun.canContinueInBackground { stopGeneration() }
        workspaceState.workspace = nil
        workspaceState.workspaceURL = nil
        workspaceState.selectedProjectPath = nil
        workspaceState.workspaceFiles = []
        workspaceState.developmentWorkspace = nil
        inspector.developmentFiles = []
        inspector.developmentChanges = []
        inspector.projectFilePreview = ""
        inspector.selectedProjectFilePath = nil
        composerAttachments.attachedFiles = []
        resetPendingAttachments()
        workspaceState.isLoadingWorkspace = false
        workspaceState.clearWorkspaceLocation()
    }

    func toggleFile(_ file: WorkspaceFile) {
        if composerAttachments.attachedFiles.contains(where: { $0.path == file.path }) {
            composerAttachments.attachedFiles.removeAll { $0.path == file.path }
            return
        }
        guard let workspace = workspaceState.workspace else { return }
        guard !composerAttachments.pendingAttachments.contains(file.path) else { return }
        let attachmentCount = composerAttachments.attachedFiles.count + composerAttachments.pendingAttachments.count
        guard attachmentCount < VyronConversationLimits.maximumAttachedFiles else {
            errorMessage = VyronStatusText.maximumAttachedFiles(VyronConversationLimits.maximumAttachedFiles)
            return
        }
        let generation = composerAttachments.generation
        composerAttachments.pendingAttachments.insert(file.path)
        Task {
            defer {
                if composerAttachments.generation == generation {
                    composerAttachments.pendingAttachments.remove(file.path)
                }
            }
            do {
                let content = try await workspace.readFile(
                    relativePath: file.path, maxBytes: VyronConversationLimits.maximumAttachedFileBytes
                )
                guard composerAttachments.generation == generation else { return }
                if composerAttachments.attachedFiles.count < VyronConversationLimits.maximumAttachedFiles,
                    !composerAttachments.attachedFiles.contains(where: { $0.path == file.path }) {
                    composerAttachments.attachedFiles.append(AttachedFile(path: file.path, content: content))
                }
            } catch {
                if composerAttachments.generation == generation { errorMessage = error.localizedDescription }
            }
        }
    }

    func openRecentProject(_ path: String) {
        let folders = sidebarProjectSourceFolders(path)
        let source = sidebarActiveProjectPath == path && folders.contains(workspaceState.workspaceURL?.path ?? "")
            ? workspaceState.workspaceURL?.path : folders.first
        guard let source else { return }
        openSidebarProjectSourceFolder(source, projectPath: path)
    }

    func openSidebarProjectSourceFolder(_ path: String, projectPath: String) {
        guard sidebarProjectSourceFolders(projectPath).contains(URL(fileURLWithPath: path).standardizedFileURL.path)
        else { return }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        if sidebarActiveProjectPath == projectPath,
            workspaceState.workspaceURL?.standardizedFileURL == url.standardizedFileURL,
            workspaceState.developmentWorkspace != nil {
            return
        }
        newConversation()
        let selectionID = prepareWorkspaceSelection(url, projectPath: projectPath)
        Task { await loadWorkspace(url, expectedSelectionID: selectionID, projectPath: projectPath) }
    }

    @discardableResult
    func prepareWorkspaceSelection(_ url: URL, projectPath: String? = nil) -> UUID {
        workspaceState.workspace = nil
        workspaceState.developmentWorkspace = nil
        workspaceState.workspaceURL = url.standardizedFileURL
        workspaceState.selectedProjectPath = projectPath ?? url.standardizedFileURL.path
        workspaceState.workspaceFiles = []
        inspector.developmentFiles = []
        inspector.developmentChanges = []
        inspector.projectFilePreview = ""
        inspector.selectedProjectFilePath = nil
        inspector.selectedChangePath = nil
        composerAttachments.attachedFiles = []
        resetPendingAttachments()
        workspaceState.isLoadingWorkspace = true
        statusMessage = VyronStatusText.openingProject
        return composerAttachments.generation
    }

    func openProjectFile(_ file: DevelopmentFile) {
        guard let project = workspaceState.developmentWorkspace else { return }
        inspector.selectedProjectFilePath = file.path
        inspector.projectFilePreview = VyronStatusText.loading
        let previewID = UUID()
        inspector.projectPreviewID = previewID
        Task {
            do {
                let content = try await project.readFile(
                    path: file.path, maxBytes: VyronWorkspaceInspectorLimits.maximumFilePreviewBytes, forEditing: false
                )
                guard inspector.projectPreviewID == previewID, workspaceState.developmentWorkspace === project else {
                    return
                }
                inspector.projectFilePreview = content
            } catch {
                if inspector.projectPreviewID == previewID, workspaceState.developmentWorkspace === project {
                    inspector.projectFilePreview = error.localizedDescription
                }
            }
        }
    }

    func refreshProject() {
        guard let project = workspaceState.developmentWorkspace else { return }
        let url = workspaceState.workspaceURL
        Task { await refreshDevelopmentState(project: project, expectedURL: url) }
    }

    func revertChange(_ path: String) {
        guard !foregroundRun.isGenerating, foregroundRun.developmentResponse == nil,
            !foregroundRun.isStoppingDevelopment, scheduledTasks.activeTaskID == nil,
            let project = workspaceState.developmentWorkspace else { return }
        let projectURL = workspaceState.workspaceURL
        Task {
            guard !foregroundRun.isGenerating, foregroundRun.developmentResponse == nil,
                !foregroundRun.isStoppingDevelopment, scheduledTasks.activeTaskID == nil,
                workspaceState.developmentWorkspace === project, workspaceState.workspaceURL == projectURL
            else { return }
            do {
                try await project.revert(path: path)
                await refreshDevelopmentState(project: project, expectedURL: projectURL)
                guard workspaceState.developmentWorkspace === project,
                    workspaceState.workspaceURL == projectURL
                else { return }
                statusMessage = VyronStatusText.revertedFile(path)
            } catch {
                if workspaceState.developmentWorkspace === project, workspaceState.workspaceURL == projectURL {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func refreshDevelopmentState(project: DevelopmentWorkspace, expectedURL: URL?) async {
        do {
            let files = try await project.listFiles(limit: VyronWorkspaceInspectorLimits.maximumListedFiles)
            let changes = await project.changes()
            guard workspaceState.developmentWorkspace === project,
                workspaceState.workspaceURL == expectedURL
            else { return }
            inspector.developmentFiles = files
            inspector.developmentChanges = changes
            if !changes.contains(where: { $0.path == inspector.selectedChangePath }) {
                inspector.selectedChangePath = changes.first?.path
            }
        } catch {
            if workspaceState.developmentWorkspace === project { errorMessage = error.localizedDescription }
        }
    }

    func handleDevelopmentEvent(_ event: DevelopmentEvent, conversationID: UUID, messageID: UUID) {
        inspector.record(event)
        inspector.trimTerminalOutput()
        guard event.kind != .commandOutput else { return }
        if selectedConversationID == conversationID {
            if event.kind == .fileChanged { refreshProject() }
            statusMessage = String(event.localizedMessage.prefix(VyronWorkspaceLimits.maximumProgressStatusCharacters))
        }
        recordDevelopmentActivity(event, conversationID: conversationID, messageID: messageID)
    }

    func resetPendingAttachments() {
        composerAttachments.resetPending()
        workspaceState.isLoadingWorkspace = false
    }
}
