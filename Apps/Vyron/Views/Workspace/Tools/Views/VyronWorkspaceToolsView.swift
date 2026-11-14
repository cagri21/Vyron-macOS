import AppKit
import SwiftUI

struct VyronWorkspaceToolsView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var locale
    @EnvironmentObject private var library: VyronWorkspaceLibraryModel
    @EnvironmentObject private var presentation: VyronWorkspaceTabsPresentation
    @State private var showsLinkEditor = false
    @State private var showsAllRecents = false
    var performTool: (@escaping () -> Void) -> Void = { $0() }

    var body: some View {
        let _ = locale
        VStack(alignment: .leading, spacing: VyronWorkspaceToolsStyle.sectionSpacing) {
            VyronWorkspaceToolsGrid(
                newPage: { performTool { presentation.newPage() } },
                performTool: { action in
                    performTool {
                        presentation.selectConversation()
                        action()
                    }
                }
            )
            suggestions
            if !library.pages.isEmpty { pages }
            recents
            if let error = library.errorMessage {
                VStack(alignment: .leading, spacing: VyronWorkspaceToolsStyle.gridSpacing) {
                    Text(error).font(VyronWorkspaceToolsStyle.captionFont).textSelection(.enabled)
                    Button(VyronToolsText.retry) { library.reload() }
                }
                .foregroundStyle(palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showsLinkEditor) {
            VyronWorkspaceLinkEditor().environmentObject(library)
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: VyronWorkspaceToolsStyle.padding) {
            HStack {
                Text(VyronToolsText.suggested).font(VyronWorkspaceToolsStyle.titleFont)
                Spacer()
                Button { showsLinkEditor = true } label: {
                    Label(VyronToolsText.addLink, systemImage: VyronSymbols.plus)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.muted)
                .font(VyronWorkspaceToolsStyle.captionFont)
            }
            if library.links.isEmpty {
                Text(VyronToolsText.noLinks)
                    .font(VyronWorkspaceToolsStyle.controlFont).foregroundStyle(palette.muted)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), spacing: VyronWorkspaceToolsStyle.padding)],
                    spacing: VyronWorkspaceToolsStyle.padding
                ) {
                    ForEach(library.links) { link in
                        Button { openLink(link) } label: {
                            VStack(spacing: VyronWorkspaceToolsStyle.padding) {
                                Image(systemName: VyronSymbols.web)
                                    .font(.system(size: VyronWorkspaceToolsStyle.shortcutIconSize))
                                    .foregroundStyle(palette.controlAccent)
                                Text(link.title).lineLimit(1).truncationMode(.tail)
                                    .font(VyronWorkspaceToolsStyle.controlFont)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: VyronWorkspaceToolsStyle.shortcutHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(link.url.absoluteString)
                        .contextMenu {
                            Button(VyronToolsText.remove, role: .destructive) { library.removeLink(link.id) }
                        }
                    }
                }
            }
        }
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: VyronWorkspaceToolsStyle.padding) {
            HStack {
                Text(VyronToolsText.recents).font(VyronWorkspaceToolsStyle.titleFont)
                Spacer()
                Button(VyronToolsText.openFile, action: chooseFile)
                    .buttonStyle(.plain).font(VyronWorkspaceToolsStyle.captionFont)
                    .foregroundStyle(palette.muted)
            }
            if library.recents.isEmpty {
                Text(VyronToolsText.noRecents)
                    .font(VyronWorkspaceToolsStyle.controlFont).foregroundStyle(palette.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(visibleRecents) { recent in
                        Button { openRecent(recent) } label: {
                            VyronWorkspaceRecentRow(item: recent)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(VyronToolsText.remove) { library.removeRecent(recent.id) }
                        }
                    }
                }
                .background(palette.surface, in: RoundedRectangle(cornerRadius: VyronWorkspaceToolsStyle.cornerRadius))
                if library.recents.count > VyronWorkspaceToolsStyle.recentLimit {
                    Button(showsAllRecents ? VyronToolsText.showLess : VyronToolsText.showAll) {
                        showsAllRecents.toggle()
                    }
                    .buttonStyle(.plain).font(VyronWorkspaceToolsStyle.captionFont)
                }
            }
        }
    }

    private var pages: some View {
        DisclosureGroup(VyronToolsText.pagesTitle) {
            VStack(spacing: 0) {
                ForEach(library.pages) { page in
                    Button {
                        performTool { presentation.openPage(page) }
                    } label: {
                        HStack(spacing: VyronWorkspaceToolsStyle.padding) {
                            Image(systemName: VyronSymbols.newPage).foregroundStyle(palette.controlAccent)
                            Text(page.displayTitle).lineLimit(1)
                            Spacer()
                            Text(page.updatedAt, style: .date)
                                .font(VyronWorkspaceToolsStyle.captionFont).foregroundStyle(palette.muted)
                        }
                        .padding(VyronWorkspaceToolsStyle.padding)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(VyronToolsText.deletePage, role: .destructive) { presentation.deletePage(page) }
                            .disabled(!presentation.canDeletePage(page))
                    }
                }
            }
        }
        .font(VyronWorkspaceToolsStyle.controlFont)
    }

    private var visibleRecents: [VyronWorkspaceRecentItem] {
        showsAllRecents ? library.recents : Array(library.recents.prefix(VyronWorkspaceToolsStyle.recentLimit))
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if NSWorkspace.shared.open(url) {
                library.recordFile(url)
            } else {
                library.errorMessage = VyronToolsText.openFailed
            }
        }
    }

    private func openLink(_ link: VyronWorkspaceLink) {
        performTool {
            if presentation.openWebsite(link.url) != nil { library.recordLink(link) }
        }
    }

    private func openRecent(_ item: VyronWorkspaceRecentItem) {
        switch item.kind {
        case .page:
            guard let page = library.pages.first(where: { "page:\($0.id.uuidString)" == item.id }) else {
                library.errorMessage = VyronToolsText.openFailed
                return
            }
            performTool { presentation.openPage(page) }
        case .file:
            guard FileManager.default.fileExists(atPath: item.url.path) else {
                library.errorMessage = VyronToolsText.missingRecentFile
                return
            }
            if NSWorkspace.shared.open(item.url) {
                library.recordFile(item.url)
            } else {
                library.errorMessage = VyronToolsText.openFailed
            }
        case .link:
            guard let link = library.links.first(where: { "link:\($0.id.uuidString)" == item.id }) else {
                library.errorMessage = VyronToolsText.openFailed
                return
            }
            openLink(link)
        }
    }
}
