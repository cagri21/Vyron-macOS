import Combine
import Foundation

@MainActor
final class VyronWorkspaceTabsModel: ObservableObject {
    @Published private(set) var tabs: [VyronWorkspaceTab]
    @Published private(set) var selectedID: UUID
    @Published var errorMessage: String?
    let conversationTabID: UUID

    init() {
        let conversation = VyronWorkspaceTab(id: UUID(), location: .conversation, title: VyronBrowserText.conversation)
        tabs = [conversation]
        selectedID = conversation.id
        conversationTabID = conversation.id
    }

    var selectedTab: VyronWorkspaceTab {
        // The conversation tab is permanent; selecting and closing preserve this invariant.
        tabs.first { $0.id == selectedID } ?? VyronWorkspaceTab(
            id: conversationTabID, location: .conversation, title: VyronBrowserText.conversation
        )
    }

    @discardableResult
    func newTab() -> UUID? {
        appendTab(location: .home, title: VyronBrowserText.newTab)
    }

    @discardableResult
    func select(_ id: UUID) -> Bool {
        guard tabs.contains(where: { $0.id == id }) else { return false }
        selectedID = id
        errorMessage = nil
        return true
    }

    @discardableResult
    func close(_ id: UUID) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }), tabs[index].canClose else { return false }
        tabs.remove(at: index)
        if selectedID == id {
            selectedID = tabs[min(index, tabs.count - 1)].id
        }
        errorMessage = nil
        return true
    }

    @discardableResult
    func openWebsite(_ url: URL, select: Bool = true) -> UUID? {
        guard VyronWorkspaceAddress.isAllowedWebsite(url) else { return nil }
        return appendTab(
            location: .website(VyronWorkspaceWebsiteLocation(url: url)), title: url.host ?? "", select: select
        )
    }

    @discardableResult
    func navigate(_ url: URL, in id: UUID) -> Bool {
        guard VyronWorkspaceAddress.isAllowedWebsite(url),
            let index = tabs.firstIndex(where: { $0.id == id }),
            tabs[index].kind == .home || tabs[index].kind == .website
        else { return false }
        tabs[index].location = .website(VyronWorkspaceWebsiteLocation(url: url))
        tabs[index].title = url.host ?? ""
        errorMessage = nil
        return true
    }

    @discardableResult
    func openPage(_ page: VyronWorkspacePage) -> UUID? {
        if let index = tabs.firstIndex(where: {
            if case .page(let location) = $0.location { return location.pageID == page.id }
            return false
        }) {
            tabs[index].title = page.displayTitle
            selectedID = tabs[index].id
            errorMessage = nil
            return selectedID
        }
        return appendTab(location: .page(VyronWorkspacePageLocation(pageID: page.id)), title: page.displayTitle)
    }

    @discardableResult
    func updateWebsiteLocation(_ update: VyronWorkspaceWebsiteUpdate) -> Bool {
        guard VyronWorkspaceAddress.isAllowedWebsite(update.url),
            let index = tabs.firstIndex(where: { $0.id == update.tabID }), tabs[index].kind == .website
        else { return false }
        tabs[index].location = .website(VyronWorkspaceWebsiteLocation(url: update.url))
        let title = update.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        tabs[index].title = title.isEmpty ? (update.url.host ?? "")
            : String(title.prefix(VyronWorkspaceTabLimits.websiteTitleCharacters))
        return true
    }

    func updatePageTitle(_ page: VyronWorkspacePage) {
        for index in tabs.indices {
            if case .page(let location) = tabs[index].location, location.pageID == page.id {
                tabs[index].title = page.displayTitle
            }
        }
    }

    func updateConversationTitle(_ title: String) {
        guard let index = tabs.firstIndex(where: { $0.id == conversationTabID }) else { return }
        tabs[index].title = title.isEmpty ? VyronBrowserText.conversation : title
    }

    private func appendTab(location: VyronWorkspaceTabLocation, title: String, select: Bool = true) -> UUID? {
        guard tabs.count < VyronWorkspaceTabLimits.maximumTabs else {
            errorMessage = VyronBrowserText.tabLimit
            return nil
        }
        let tab = VyronWorkspaceTab(id: UUID(), location: location, title: title)
        tabs.append(tab)
        if select { selectedID = tab.id }
        errorMessage = nil
        return tab.id
    }
}
