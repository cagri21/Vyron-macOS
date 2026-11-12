import SwiftUI
import VyronCore

struct VyronPluginsView: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @ObservedObject var connections: MCPConnectionsModel
    @ObservedObject var presentation: VyronPluginsPresentation

    private var isLocked: Bool { !model.canManageMCPConnections }
    private var profiles: [MCPConnectionProfile] {
        presentation.visibleProfiles(
            connections.profiles,
            connectedIDs: Set(connections.profiles.filter { connections.isConnected($0.id) }.map(\.id))
        )
    }
    private var hasMatchingCatalog: Bool {
        presentation.filter == .all && (
            presentation.matchesSearch(VyronPluginText.penpotName, detail: VyronPluginText.penpotSummary)
                || presentation.matchesSearch(VyronPluginText.customName, detail: VyronPluginText.customSummary)
                || presentation.matchesSearch(VyronPluginText.codexName, detail: VyronPluginText.codexSummary)
                || presentation.matchesSearch(
                    VyronPluginText.agentBridgeName,
                    detail: VyronPluginText.agentBridgeSummary
                )
        )
    }

    var body: some View {
        let _ = localizationLocale
        ScrollView {
            VStack(alignment: .leading, spacing: VyronPluginsStyle.sectionSpacing) {
                header
                notices
                if let selected = connections.profiles.first(where: { $0.id == presentation.selectedConnectionID }) {
                    VyronPluginDetailView(connections: connections, presentation: presentation, profile: selected)
                } else {
                    catalog
                }
                Spacer(minLength: VyronPluginsStyle.sectionSpacing)
                Text(VyronPluginText.securityNote)
                    .font(VyronPluginsStyle.caption).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, VyronPluginsStyle.contentPadding)
            .padding(.top, VyronPluginsStyle.headerTopPadding)
            .padding(.bottom, VyronPluginsStyle.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.canvas)
        .sheet(item: $presentation.editingProfile) { profile in
            VyronMCPConnectionEditor(connections: connections, initial: profile).environmentObject(model)
        }
        .alert(
            VyronPluginText.removeTitle,
            isPresented: Binding(
                get: { presentation.removingProfile != nil },
                set: { if !$0 { presentation.removingProfile = nil } }
            ),
            presenting: presentation.removingProfile
        ) { profile in
            Button(VyronPluginText.removeAction, role: .destructive) {
                guard !isLocked else { return }
                connections.remove(profile.id)
                presentation.removingProfile = nil
            }
            Button(VyronPluginText.cancel, role: .cancel) { presentation.removingProfile = nil }
        } message: { _ in
            Text(VyronPluginText.removeBody)
        }
        .onChange(of: connections.profiles) { _, profiles in presentation.reconcileSelection(with: profiles) }
        .onChange(of: presentation.searchQuery) { _, _ in
            if presentation.selectedConnectionID != nil { presentation.showSearchResults() }
        }
        .onDisappear {
            presentation.editingProfile = nil
            presentation.removingProfile = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: VyronPluginsStyle.rowSpacing) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: VyronPluginsStyle.rowSpacing) {
                    Text(VyronPluginText.title).font(VyronPluginsStyle.title)
                    Spacer(minLength: VyronPluginsStyle.rowSpacing)
                    toolbar
                }
                VStack(alignment: .leading, spacing: VyronPluginsStyle.rowSpacing) {
                    Text(VyronPluginText.title).font(VyronPluginsStyle.title)
                    toolbar
                }
            }
            Text(VyronPluginText.subtitle).font(VyronPluginsStyle.body).foregroundStyle(Palette.muted)
        }
    }

    private var toolbar: some View {
        HStack(spacing: VyronPluginsStyle.rowSpacing) {
            searchField
            Button {
                connections.refreshProfiles()
                presentation.reconcileSelection(with: connections.profiles)
            } label: {
                Image(systemName: VyronSymbols.refresh)
                    .frame(width: VyronPluginsStyle.toolbarControlSize, height: VyronPluginsStyle.toolbarControlSize)
            }
            .buttonStyle(.plain).foregroundStyle(Palette.muted)
            .help(VyronPluginText.refresh).accessibilityLabel(VyronPluginText.refresh)
            .disabled(isLocked)
            Button { model.openSettings(.plugins) } label: {
                Image(systemName: VyronSymbols.settings)
                    .frame(width: VyronPluginsStyle.toolbarControlSize, height: VyronPluginsStyle.toolbarControlSize)
            }
            .buttonStyle(.plain).foregroundStyle(Palette.muted)
            .help(VyronPluginText.settings).accessibilityLabel(VyronPluginText.settings)
            addMenu
        }
        .font(VyronPluginsStyle.body)
    }

    private var searchField: some View {
        HStack(spacing: VyronPluginsStyle.compactSpacing) {
            Image(systemName: VyronSymbols.search).foregroundStyle(Palette.muted)
            TextField(VyronPluginText.search, text: $presentation.searchQuery)
                .textFieldStyle(.plain)
                .accessibilityLabel(VyronPluginText.search)
            if !presentation.searchQuery.isEmpty {
                Button { presentation.searchQuery = "" } label: {
                    Image(systemName: VyronSymbols.close)
                }
                .buttonStyle(.plain).foregroundStyle(Palette.muted)
                .help(VyronPluginText.clearSearch).accessibilityLabel(VyronPluginText.clearSearch)
            }
        }
        .padding(.horizontal, VyronPluginsStyle.rowSpacing)
        .frame(width: VyronPluginsStyle.searchWidth, height: VyronPluginsStyle.searchHeight)
        .overlay(Capsule().stroke(Palette.border))
    }

    private var addMenu: some View {
        Menu {
            Button(VyronPluginText.addConnection) { presentation.addConnection() }
            Button(VyronPluginText.addPenpot) { presentation.addPenpot() }
            Button(VyronPluginText.addCodex) { presentation.addCodexCatalog() }
            Button(VyronPluginText.addAgentBridge) {
                presentation.addAgentCatalog(projectDirectory: model.workspaceState.workspaceURL)
            }
            Divider()
            Button(VyronPluginText.importPenpot) { connections.importExistingPenpot() }
        } label: {
            HStack(spacing: VyronPluginsStyle.compactSpacing) {
                Text(VyronPluginText.add)
                Image(systemName: VyronSymbols.chevronDown)
            }
            .font(VyronPluginsStyle.emphasizedAction)
            .padding(.horizontal, VyronPluginsStyle.rowSpacing)
            .frame(height: VyronPluginsStyle.searchHeight)
            .foregroundStyle(Palette.text)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .tint(Palette.text)
        .font(VyronPluginsStyle.emphasizedAction)
        .disabled(isLocked)
    }

    @ViewBuilder
    private var notices: some View {
        if isLocked {
            Label(VyronPluginText.reviewNote, systemImage: VyronSymbols.hand)
                .font(VyronPluginsStyle.caption).foregroundStyle(Palette.muted)
        }
        if let error = presentation.catalogError ?? connections.error {
            Label {
                Text(verbatim: error).textSelection(.enabled)
            } icon: {
                Image(systemName: VyronSymbols.warning)
            }
            .font(VyronPluginsStyle.body).foregroundStyle(Palette.warning)
        }
    }

    private var catalog: some View {
        VStack(alignment: .leading, spacing: VyronPluginsStyle.sectionSpacing) {
            HStack(spacing: VyronPluginsStyle.compactSpacing) {
                catalogTab(VyronPluginText.publicCatalog, filter: .all)
                catalogTab(VyronPluginText.personalCatalog, filter: .installed)
                Spacer(minLength: 0)
                if presentation.filter != .all {
                    Toggle(
                        VyronPluginText.connected,
                        isOn: Binding(
                            get: { presentation.filter == .connected },
                            set: { presentation.filter = $0 ? .connected : .installed }
                        )
                    )
                    .toggleStyle(.checkbox).font(VyronPluginsStyle.action).foregroundStyle(Palette.muted)
                }
            }
            if !profiles.isEmpty {
                VStack(alignment: .leading, spacing: VyronPluginsStyle.rowSpacing) {
                    Text(VyronPluginText.installed).font(VyronPluginsStyle.sectionTitle)
                    VyronPluginCatalogGrid {
                        ForEach(profiles) { profile in
                            VyronPluginInstalledRow(
                                connections: connections,
                                presentation: presentation,
                                profile: profile,
                                isLocked: isLocked
                            )
                        }
                    }
                }
            }
            if hasMatchingCatalog { availablePlugins }
            if profiles.isEmpty && !hasMatchingCatalog { emptyState }
        }
    }

    private func catalogTab(_ title: String, filter: VyronPluginFilter) -> some View {
        let selected = filter == .all ? presentation.filter == .all : presentation.filter != .all
        return Button { presentation.filter = filter } label: {
            Text(verbatim: title).font(VyronPluginsStyle.action)
                .padding(.horizontal, VyronPluginsStyle.tabHorizontalPadding)
                .padding(.vertical, VyronPluginsStyle.tabVerticalPadding)
                .background(selected ? Palette.raised : .clear, in: Capsule())
        }
        .buttonStyle(.plain).foregroundStyle(selected ? Palette.text : Palette.muted)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: VyronPluginsStyle.rowSpacing) {
            Text(connections.profiles.isEmpty && presentation.searchQuery.isEmpty
                ? VyronPluginText.emptyTitle : VyronPluginText.noResults)
                .font(VyronPluginsStyle.sectionTitle)
            if connections.profiles.isEmpty && presentation.searchQuery.isEmpty {
                Text(VyronPluginText.emptyBody).font(VyronPluginsStyle.body).foregroundStyle(Palette.muted)
            }
        }
        .padding(.vertical, VyronPluginsStyle.cardPadding)
    }

    private var availablePlugins: some View {
        VStack(alignment: .leading, spacing: VyronPluginsStyle.sectionSpacing) {
            if presentation.matchesSearch(VyronPluginText.penpotName, detail: VyronPluginText.penpotSummary) {
                VStack(alignment: .leading, spacing: VyronPluginsStyle.rowSpacing) {
                    Text(VyronPluginText.design).font(VyronPluginsStyle.sectionTitle)
                    VyronPluginCatalogGrid {
                        VyronPluginCatalogCard(isPenpot: true, isLocked: isLocked) { presentation.addPenpot() }
                    }
                }
            }
            if presentation.matchesSearch(VyronPluginText.customName, detail: VyronPluginText.customSummary)
                || presentation.matchesSearch(VyronPluginText.codexName, detail: VyronPluginText.codexSummary)
                || presentation.matchesSearch(
                    VyronPluginText.agentBridgeName,
                    detail: VyronPluginText.agentBridgeSummary
                ) {
                VStack(alignment: .leading, spacing: VyronPluginsStyle.rowSpacing) {
                    Text(VyronPluginText.tools).font(VyronPluginsStyle.sectionTitle)
                    VyronPluginCatalogGrid {
                        if presentation.matchesSearch(
                            VyronPluginText.customName,
                            detail: VyronPluginText.customSummary
                        ) {
                            VyronPluginCatalogCard(isPenpot: false, isLocked: isLocked) { presentation.addConnection() }
                        }
                        if presentation.matchesSearch(VyronPluginText.codexName, detail: VyronPluginText.codexSummary) {
                            VyronCodexCatalogCard(isLocked: isLocked) { presentation.addCodexCatalog() }
                        }
                        if presentation.matchesSearch(
                            VyronPluginText.agentBridgeName,
                            detail: VyronPluginText.agentBridgeSummary
                        ) {
                            VyronAgentCatalogCard(isLocked: isLocked) {
                                presentation.addAgentCatalog(projectDirectory: model.workspaceState.workspaceURL)
                            }
                        }
                    }
                }
            }
        }
    }
}
