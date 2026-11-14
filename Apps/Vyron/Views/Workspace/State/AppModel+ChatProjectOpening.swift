import AppKit
import Foundation

extension AppModel {
    func chatProjectURL(for id: UUID) -> URL? {
        guard chatActions(for: id) != nil,
            let conversation = conversations.first(where: { $0.id == id }),
            let path = conversation.workspacePath ?? conversation.sidebarProjectPath else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
            isDirectory.boolValue else { return nil }
        return url
    }

    func canOpenChatProjectInXcode(_ id: UUID) -> Bool {
        chatProjectURL(for: id) != nil && xcodeApplicationURL != nil
    }

    @discardableResult
    func openChatProjectInFinder(_ id: UUID) -> Bool {
        guard let url = chatProjectURL(for: id) else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    @discardableResult
    func openChatProjectInXcode(_ id: UUID) -> Bool {
        guard let url = chatProjectURL(for: id), let application = xcodeApplicationURL else { return false }
        Task {
            do {
                try await openInXcode([url], application: application)
            } catch {
                if selectedConversationID == id { errorMessage = error.localizedDescription }
            }
        }
        return true
    }

    func openChangedProject(path: String, changedPaths: [String], conversationID: UUID) {
        guard path.hasPrefix("/") else {
            errorMessage = VyronToolsText.openFailed
            return
        }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        Task {
            let destination = await Task.detached(priority: .userInitiated) {
                VyronChangedProjectDestination.resolve(root: root, changedPaths: changedPaths)
            }.value
            guard selectedConversationID == conversationID, !isShuttingDown else { return }
            guard let destination else {
                errorMessage = VyronToolsText.openFailed
                return
            }

            guard destination.opensInXcode, let application = xcodeApplicationURL else {
                let folder = destination.opensInXcode ? root : destination.projectURL
                if !NSWorkspace.shared.open(folder) { errorMessage = VyronToolsText.openFailed }
                return
            }
            do {
                try await openInXcode([destination.projectURL], application: application)
                if !isShuttingDown, !destination.changedFileURLs.isEmpty {
                    try await openInXcode(destination.changedFileURLs, application: application)
                }
            } catch {
                if selectedConversationID == conversationID { errorMessage = error.localizedDescription }
            }
        }
    }

    private var xcodeApplicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: VyronMacWorkApplicationIDs.xcode)
    }

    private func openInXcode(_ urls: [URL], application: URL) async throws {
        _ = try await NSWorkspace.shared.open(
            urls, withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
