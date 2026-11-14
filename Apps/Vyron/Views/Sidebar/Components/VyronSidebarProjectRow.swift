import SwiftUI
import VyronCore

struct VyronSidebarProjectRow<MenuContent: View>: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @State private var isHovered = false
    @State private var showsInfo = false
    @State private var showsEditor = false
    @State private var suppressesInfoUntilExit = false
    @State private var hoverTask: Task<Void, Never>?
    let path: String
    let detail: String?
    let isSearching: Bool
    @ViewBuilder let menu: () -> MenuContent

    private var expanded: Bool { isSearching || model.sidebarState.sidebarOrganization.isProjectExpanded(path) }
    private var selected: Bool { model.sidebarActiveProjectPath == path }
    private var showsActions: Bool { isHovered || selected }
    private var activeChatCount: Int { model.sidebarProjectActiveChatCount(path) }

    var body: some View {
        let _ = localizationLocale
        HStack(spacing: 0) {
            Button {
                dismissInfo()
                model.setSidebarProjectExpanded(path, expanded: !expanded)
            } label: {
                Image(systemName: disclosureSymbol)
                    .foregroundStyle(palette.muted)
                    .frame(width: VyronSidebarStyle.disclosureWidth, height: VyronSidebarStyle.rowHeight)
                    .contentShape(Rectangle())
            }
            .disabled(isSearching)
            .help(isSearching ? VyronSidebarText.clearSearchToExpand : expansionLabel)
            .accessibilityLabel(expansionLabel)

            Button {
                dismissInfo()
                model.openRecentProject(path)
            } label: {
                VStack(alignment: .leading, spacing: VyronSidebarStyle.rowSpacing) {
                    Text(verbatim: model.sidebarProjectName(path)).lineLimit(1)
                    if let detail {
                        Text(verbatim: detail)
                            .font(VyronSidebarStyle.captionFont)
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: VyronSidebarStyle.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
            .onHover { hovering in
                if !hovering { suppressesInfoUntilExit = false }
                scheduleInfo(visible: hovering)
            }
            .popover(isPresented: $showsInfo, arrowEdge: .trailing) {
                VyronSidebarProjectInfo(path: path) {
                    dismissInfo()
                    showsEditor = true
                }
                .environmentObject(model)
                .onHover { hovering in scheduleInfo(visible: hovering, immediately: true) }
            }

            if activeChatCount > 0 {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: VyronSidebarStyle.projectActionWidth, height: VyronSidebarStyle.rowHeight)
                    .help(VyronSidebarText.projectActiveCount(activeChatCount))
                    .accessibilityLabel(VyronSidebarText.projectActiveCount(activeChatCount))
            }

            Menu(content: menu) {
                Image(systemName: VyronSymbols.ellipsis)
                    .frame(width: VyronSidebarStyle.projectActionWidth, height: VyronSidebarStyle.rowHeight)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(VyronSidebarText.projectActions)
            .accessibilityLabel(VyronSidebarText.projectActions)
            .opacity(showsActions ? 1 : 0)
            .onHover { if $0 { dismissInfo() } }

            Button {
                dismissInfo()
                model.requestNewTask(projectPath: path)
            } label: {
                Image(systemName: VyronSymbols.newTask)
                    .frame(width: VyronSidebarStyle.projectActionWidth, height: VyronSidebarStyle.rowHeight)
                    .contentShape(Rectangle())
            }
            .help(VyronSidebarText.newProjectChat)
            .accessibilityLabel(VyronSidebarText.newProjectChat)
            .opacity(showsActions ? 1 : 0)
        }
        .font(VyronSidebarStyle.rowFont)
        .foregroundStyle(palette.text)
        .buttonStyle(.plain)
        .modifier(VyronSidebarRowBackground(isSelected: selected))
        .contextMenu { menu() }
        .onHover { isHovered = $0 }
        .onChange(of: isEnabled) { _, isEnabled in
            guard !isEnabled else { return }
            isHovered = false
            dismissInfo()
            suppressesInfoUntilExit = false
        }
        .onDisappear { dismissInfo() }
        .sheet(isPresented: $showsEditor) {
            VyronSidebarProjectEditor(projectPath: path).environmentObject(model)
        }
    }

    private var expansionLabel: String {
        expanded ? VyronSidebarText.collapseProject : VyronSidebarText.expandProject
    }

    private var disclosureSymbol: String {
        if isHovered { return expanded ? VyronSymbols.chevronDown : VyronSymbols.chevronRight }
        return expanded ? VyronSymbols.folderFilled : VyronSymbols.folder
    }

    private func scheduleInfo(visible: Bool, immediately: Bool = false) {
        hoverTask?.cancel()
        guard !visible || (isEnabled && !suppressesInfoUntilExit && !showsEditor) else { return }
        hoverTask = Task { @MainActor in
            do {
                let delay = visible ? VyronSidebarStyle.projectHoverDelay : VyronSidebarStyle.projectHoverDismissDelay
                if !immediately || !visible { try await Task.sleep(for: delay) }
                guard !Task.isCancelled else { return }
                showsInfo = visible
            } catch is CancellationError {
                return
            } catch {
                showsInfo = false
            }
        }
    }

    private func dismissInfo() {
        hoverTask?.cancel()
        showsInfo = false
        suppressesInfoUntilExit = true
    }
}
