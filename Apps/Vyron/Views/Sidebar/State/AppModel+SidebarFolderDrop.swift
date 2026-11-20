import Foundation
import VyronCore

extension AppModel {
    func openDroppedProjectFolder(at url: URL) -> String? {
        guard !isShuttingDown, url.isFileURL else { return nil }
        let folder: URL
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            guard values.isDirectory == true, values.isPackage != true else { return nil }
            folder = try ProjectWorkspace(rootURL: url).rootURL
        } catch {
            errorMessage = VyronStatusText.workspaceOpenFailure(error.localizedDescription)
            return nil
        }

        if let projectPath = sidebarProjectPath(forDroppedFolder: folder, originalURL: url) {
            guard changeSidebar({ try Self.expandSidebarProject(projectPath, in: &$0) }) else { return nil }
            sidebarState.sidebarSearchText = ""
            appNavigation.destination = .workspace
            if sidebarProjectSourceFolders(projectPath).contains(folder.path) {
                openSidebarProjectSourceFolder(folder.path, projectPath: projectPath)
            } else {
                openRecentProject(projectPath)
            }
            return projectPath
        }

        sidebarState.sidebarSearchText = ""
        appNavigation.destination = .workspace
        openAddedProjectFolder(folder)
        return folder.path
    }

    private func sidebarProjectPath(forDroppedFolder folder: URL, originalURL: URL) -> String? {
        let organization = sidebarState.sidebarOrganization
        let path = folder.path
        let originalPath = originalURL.standardizedFileURL.path
        if organization.contains(.project(path)) { return path }
        if organization.contains(.project(originalPath)) { return originalPath }
        if let activePath = sidebarActiveProjectPath, organization.contains(.project(activePath)),
            organization.projectSourceFolders(for: activePath).contains(path) {
            return activePath
        }
        return organization.allProjects.first { organization.projectSourceFolders(for: $0).contains(path) }
    }
}
