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
        chatProjectURL(for: id) != nil
            && NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") != nil
    }

    @discardableResult
    func openChatProjectInFinder(_ id: UUID) -> Bool {
        guard let url = chatProjectURL(for: id) else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    @discardableResult
    func openChatProjectInXcode(_ id: UUID) -> Bool {
        guard let url = chatProjectURL(for: id),
            let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode")
        else { return false }
        Task {
            do {
                _ = try await NSWorkspace.shared.open(
                    [url], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()
                )
            } catch {
                if selectedConversationID == id { errorMessage = error.localizedDescription }
            }
        }
        return true
    }
}
