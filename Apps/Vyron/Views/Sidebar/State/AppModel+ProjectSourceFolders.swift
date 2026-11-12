import AppKit
import Foundation
import VyronCore

extension AppModel {
    var sidebarActiveProjectPath: String? {
        workspaceState.selectedProjectPath ?? workspaceState.workspaceURL?.standardizedFileURL.path
    }

    var selectedProjectSourceFolderIsAttached: Bool {
        guard let owner = sidebarActiveProjectPath else { return true }
        guard let source = workspaceState.workspaceURL?.standardizedFileURL.path else { return false }
        guard sidebarState.sidebarOrganization.contains(.project(owner)) else { return true }
        return sidebarProjectSourceFolders(owner).contains(source)
    }

    func sidebarProjectSourceFolders(_ path: String) -> [String] {
        sidebarState.sidebarOrganization.projectSourceFolders(for: path)
    }

    func canEditSidebarProjectFolders(_ path: String) -> Bool {
        canRemoveSidebarProject(path) && !(sidebarActiveProjectPath == path && workspaceState.isLoadingWorkspace)
    }

    func chooseSidebarProjectSourceFolders() -> [String] {
        let panel = NSOpenPanel()
        panel.title = VyronSidebarText.addFolder
        panel.prompt = VyronSidebarText.addFolder
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.map(\.standardizedFileURL.path)
    }

    @discardableResult
    func saveSidebarProject(_ path: String, name: String, sourceFolders: [String]) -> Bool {
        let previousSources = sidebarProjectSourceFolders(path)
        let foldersChanged = sourceFolders != previousSources
        guard !foldersChanged || canEditSidebarProjectFolders(path) else {
            errorMessage = VyronSidebarText.sourceFoldersBusy
            return false
        }
        let validated: [String]
        do {
            validated = foldersChanged ? try VyronSidebarSourceFolderValidator.validate(sourceFolders) : previousSources
        } catch {
            errorMessage = VyronSidebarText.invalidSourceFolders
            return false
        }
        guard changeSidebar({ try $0.updateProject(path: path, name: name, sourceFolders: validated) }) else {
            return false
        }
        let addedFolders = validated.filter { !previousSources.contains($0) }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        if sidebarActiveProjectPath == path,
            let activeSource = workspaceState.workspaceURL?.standardizedFileURL.path, !validated.contains(activeSource),
            let nextSource = validated.first {
            openSidebarProjectSourceFolder(nextSource, projectPath: path)
        }
        initializeAddedProjectFolders(addedFolders)
        return true
    }

    func restoreSidebarProjectSelection() {
        guard let source = workspaceState.workspaceURL?.standardizedFileURL.path else {
            workspaceState.selectedProjectPath = nil
            return
        }
        let saved = workspaceState.savedSelectedProjectPath
        if let saved, sidebarState.sidebarOrganization.contains(.project(saved)),
            sidebarProjectSourceFolders(saved).contains(source) {
            workspaceState.selectedProjectPath = saved
        } else {
            workspaceState.selectedProjectPath = source
        }
    }

    func registerLoadedSidebarProject(_ path: String, sourceFolder: String) {
        changeSidebar { organization in
            if !organization.contains(.project(path)) {
                try organization.updateProject(
                    path: path,
                    name: URL(fileURLWithPath: path).lastPathComponent,
                    sourceFolders: [sourceFolder]
                )
            }
        }
    }
}
