import Combine
import Foundation

@MainActor
final class VyronWorkspaceLibraryModel: ObservableObject {
    @Published private(set) var pages: [VyronWorkspacePage] = []
    @Published private(set) var links: [VyronWorkspaceLink] = []
    @Published private(set) var recents: [VyronWorkspaceRecentItem] = []
    @Published var errorMessage: String?
    private let store: VyronWorkspaceLibraryStore
    private var writable = false
    private var loadError: String?

    init(directory: URL? = nil) {
        store = VyronWorkspaceLibraryStore(directory: directory)
        reload()
    }

    @discardableResult
    func reload() -> Bool {
        do {
            let snapshot = try store.load()
            publish(snapshot)
            writable = true
            loadError = nil
            errorMessage = nil
            return true
        } catch {
            writable = false
            loadError = VyronToolsText.libraryLoadFailed(error.localizedDescription)
            errorMessage = loadError
            return false
        }
    }

    @discardableResult
    func savePage(_ page: VyronWorkspacePage) -> Bool {
        var snapshot = currentSnapshot
        var saved = page
        saved.title = page.title.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.updatedAt = Date()
        if let index = snapshot.pages.firstIndex(where: { $0.id == saved.id }) {
            snapshot.pages[index] = saved
        } else {
            snapshot.pages.insert(saved, at: 0)
        }
        snapshot.pages.sort { $0.updatedAt > $1.updatedAt }
        addRecent(pageReference(saved), to: &snapshot)
        return commit(snapshot)
    }

    @discardableResult
    func removePage(_ id: UUID) -> Bool {
        var snapshot = currentSnapshot
        snapshot.pages.removeAll { $0.id == id }
        snapshot.recents.removeAll { $0.id == "page:\(id.uuidString)" }
        return commit(snapshot)
    }

    @discardableResult
    func addLink(title: String, address: String) -> Bool {
        guard let url = VyronWorkspaceLibraryStore.validatedWebsite(address) else {
            errorMessage = VyronToolsText.invalidLink
            return false
        }
        var snapshot = currentSnapshot
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = cleanTitle.isEmpty ? (url.host ?? url.absoluteString) : cleanTitle
        if let index = snapshot.links.firstIndex(where: { $0.url == url }) {
            snapshot.links[index].title = displayTitle
            let id = "link:\(snapshot.links[index].id.uuidString)"
            if let recentIndex = snapshot.recents.firstIndex(where: { $0.id == id }) {
                snapshot.recents[recentIndex].reference.title = displayTitle
            }
        } else {
            snapshot.links.append(VyronWorkspaceLink(title: displayTitle, url: url))
        }
        return commit(snapshot)
    }

    @discardableResult
    func removeLink(_ id: UUID) -> Bool {
        var snapshot = currentSnapshot
        snapshot.links.removeAll { $0.id == id }
        snapshot.recents.removeAll { $0.id == "link:\(id.uuidString)" }
        return commit(snapshot)
    }

    @discardableResult
    func recordPage(_ page: VyronWorkspacePage) -> Bool {
        guard let saved = pages.first(where: { $0.id == page.id }) else { return false }
        var snapshot = currentSnapshot
        addRecent(pageReference(saved), to: &snapshot)
        return commit(snapshot)
    }

    @discardableResult
    func recordFile(_ url: URL) -> Bool {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = VyronToolsText.missingRecentFile
            return false
        }
        let file = url.standardizedFileURL
        let reference = VyronWorkspaceRecentReference(
            kind: .file, id: "file:\(file.path)",
            title: String(file.lastPathComponent.prefix(VyronWorkspaceLibraryLimits.titleCharacters)), url: file
        )
        var snapshot = currentSnapshot
        addRecent(reference, to: &snapshot)
        return commit(snapshot)
    }

    @discardableResult
    func recordLink(_ link: VyronWorkspaceLink) -> Bool {
        guard links.contains(where: { $0.id == link.id && $0.url == link.url }) else { return false }
        let reference = VyronWorkspaceRecentReference(
            kind: .link, id: "link:\(link.id.uuidString)", title: link.title, url: link.url
        )
        var snapshot = currentSnapshot
        addRecent(reference, to: &snapshot)
        return commit(snapshot)
    }

    @discardableResult
    func removeRecent(_ id: String) -> Bool {
        var snapshot = currentSnapshot
        snapshot.recents.removeAll { $0.id == id }
        return commit(snapshot)
    }

    private var currentSnapshot: VyronWorkspaceLibrarySnapshot {
        VyronWorkspaceLibrarySnapshot(pages: pages, links: links, recents: recents)
    }

    private func pageReference(_ page: VyronWorkspacePage) -> VyronWorkspaceRecentReference {
        // A UUID always produces a valid URL. Construct components without a force operation.
        var components = URLComponents()
        components.scheme = "vyron-page"
        components.host = page.id.uuidString
        return VyronWorkspaceRecentReference(
            kind: .page, id: "page:\(page.id.uuidString)", title: page.displayTitle,
            url: components.url ?? store.directory.appendingPathComponent(page.id.uuidString)
        )
    }

    private func addRecent(_ reference: VyronWorkspaceRecentReference, to snapshot: inout VyronWorkspaceLibrarySnapshot) {
        snapshot.recents.removeAll { $0.id == reference.id }
        snapshot.recents.insert(VyronWorkspaceRecentItem(reference: reference, openedAt: Date()), at: 0)
        snapshot.recents = Array(snapshot.recents.prefix(VyronWorkspaceLibraryLimits.recentItems))
    }

    private func commit(_ snapshot: VyronWorkspaceLibrarySnapshot) -> Bool {
        guard writable else {
            errorMessage = loadError
            return false
        }
        do {
            try store.save(snapshot)
            publish(snapshot)
            errorMessage = nil
            return true
        } catch {
            errorMessage = VyronToolsText.librarySaveFailed(error.localizedDescription)
            return false
        }
    }

    private func publish(_ snapshot: VyronWorkspaceLibrarySnapshot) {
        pages = snapshot.pages
        links = snapshot.links
        recents = snapshot.recents
    }
}
