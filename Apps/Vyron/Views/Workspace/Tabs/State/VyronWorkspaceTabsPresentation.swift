import Combine
import Foundation
import VyronCore

@MainActor
final class VyronWorkspaceTabsPresentation: ObservableObject {
    let tabs = VyronWorkspaceTabsModel()
    let library: VyronWorkspaceLibraryModel
    @Published private(set) var browsers: [UUID: VyronWorkspaceBrowserModel] = [:]
    @Published private(set) var pageSessions: [UUID: VyronWorkspacePageSession] = [:]
    @Published var pendingCloseID: UUID?
    @Published var addressError: String?
    private var subscriptions: Set<AnyCancellable> = []

    init(library: VyronWorkspaceLibraryModel? = nil) {
        self.library = library ?? VyronWorkspaceLibraryModel()
        tabs.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
    }

    var selectedBrowser: VyronWorkspaceBrowserModel? { browsers[tabs.selectedID] }

    @discardableResult
    func newTab() -> UUID? {
        addressError = nil
        return tabs.newTab()
    }

    @discardableResult
    func openWebsite(_ url: URL) -> UUID? {
        guard let id = tabs.openWebsite(url) else { return nil }
        browsers[id] = VyronWorkspaceBrowserModel(url: url)
        addressError = nil
        return id
    }

    func readWebsite(_ url: URL, selectTab: Bool) async throws -> VyronWebPage {
        try Task.checkCancellation()
        guard VyronWorkspaceBrowserPolicy.allows(url) else {
            throw VyronWorkspaceBrowserReadError(message: VyronBrowserText.invalidAddress)
        }
        let select = selectTab && tabs.selectedID == tabs.conversationTabID
        guard let id = tabs.openWebsite(url, select: select) else {
            throw VyronWorkspaceBrowserReadError(message: VyronBrowserText.tabLimit)
        }
        let browser = VyronWorkspaceBrowserModel(url: url, renderedReader: VyronWorkspaceBrowserReader())
        browsers[id] = browser
        addressError = nil
        defer {
            if select, tabs.selectedID == id { selectConversation() }
        }
        do {
            return try await browser.readRenderedPage()
        } catch is CancellationError {
            try Task.checkCancellation()
            throw CocoaError(.userCancelled)
        }
    }

    @discardableResult
    func openPage(_ page: VyronWorkspacePage) -> UUID? {
        guard let id = tabs.openPage(page) else { return nil }
        if pageSessions[id] == nil {
            pageSessions[id] = VyronWorkspacePageSession(
                page: page, isSaved: library.pages.contains(where: { $0.id == page.id })
            )
        }
        if let session = pageSessions[id] { tabs.updatePageTitle(session.draft) }
        if library.pages.contains(where: { $0.id == page.id }) { library.recordPage(page) }
        addressError = nil
        return id
    }

    func newPage() { openPage(VyronWorkspacePage()) }

    @discardableResult
    func submitAddress(_ input: String) -> Bool {
        guard case .website(let location) = VyronWorkspaceAddress.resolve(input) else {
            addressError = VyronBrowserText.invalidAddress
            return false
        }
        switch tabs.selectedTab.location {
        case .home, .website:
            let id = tabs.selectedID
            guard tabs.navigate(location.url, in: id) else { return false }
            if let browser = browsers[id] {
                browser.navigate(to: location.url)
            } else {
                browsers[id] = VyronWorkspaceBrowserModel(url: location.url)
            }
            addressError = nil
            return true
        case .conversation, .page:
            return openWebsite(location.url) != nil
        }
    }

    func selectConversation() { tabs.select(tabs.conversationTabID) }

    func requestClose(_ id: UUID) {
        guard id != tabs.conversationTabID else { return }
        if pageSessions[id]?.hasChanges == true {
            pendingCloseID = id
        } else {
            close(id)
        }
    }

    func discardPendingClose(_ id: UUID) {
        close(id)
        pendingCloseID = nil
    }

    func savePendingClose(_ id: UUID) {
        if savePage(in: id) {
            close(id)
        } else {
            addressError = library.errorMessage
        }
        pendingCloseID = nil
    }

    @discardableResult
    func savePage(in id: UUID) -> Bool {
        guard let session = pageSessions[id], library.savePage(session.draft),
            let saved = library.pages.first(where: { $0.id == session.draft.id })
        else { return false }
        session.didSave(saved)
        tabs.updatePageTitle(saved)
        return true
    }

    func canDeletePage(_ page: VyronWorkspacePage) -> Bool {
        !pageSessions.values.contains { $0.draft.id == page.id && $0.hasChanges }
    }

    func deletePage(_ page: VyronWorkspacePage) {
        guard canDeletePage(page), library.removePage(page.id) else { return }
        let matching = pageSessions.filter { $0.value.draft.id == page.id }.map(\.key)
        for id in matching { close(id) }
    }

    private func close(_ id: UUID) {
        guard tabs.close(id) else { return }
        browsers[id]?.stop()
        browsers.removeValue(forKey: id)
        pageSessions.removeValue(forKey: id)
        addressError = nil
    }
}
