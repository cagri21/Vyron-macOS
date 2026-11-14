import AppKit
import SwiftUI
import VyronCore

struct VyronSkillsView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @ObservedObject var presentation: VyronSkillsPresentation
    let projectDirectory: URL?

    var body: some View {
        let _ = localizationLocale
        ScrollView {
            VStack(alignment: .leading, spacing: VyronPluginsStyle.sectionSpacing) {
                header
                if presentation.hasLoadError {
                    HStack(spacing: VyronPluginsStyle.rowSpacing) {
                        Label(VyronSkillText.loadFailed, systemImage: VyronSymbols.warning)
                            .foregroundStyle(palette.danger)
                        Button(VyronSkillText.retry) { presentation.refresh() }
                            .buttonStyle(.plain)
                    }
                    .font(VyronPluginsStyle.body)
                }
                if let skill = presentation.selectedSkill {
                    VyronSkillDetailView(skill: skill) { presentation.showList() }
                } else {
                    catalog
                }
            }
            .padding(.horizontal, VyronPluginsStyle.contentPadding)
            .padding(.top, VyronPluginsStyle.headerTopPadding)
            .padding(.bottom, VyronPluginsStyle.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.canvas)
        .task(id: VyronSkillLoadRequest(projectDirectory: projectDirectory, refreshID: presentation.refreshID)) {
            await presentation.load(projectDirectory: projectDirectory)
        }
        .onChange(of: presentation.searchQuery) { _, _ in presentation.showList() }
        .onChange(of: presentation.filter) { _, _ in presentation.showList() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: VyronPluginsStyle.rowSpacing) {
            HStack(spacing: VyronPluginsStyle.rowSpacing) {
                Text(VyronSkillText.title).font(VyronPluginsStyle.title)
                Spacer(minLength: 0)
                searchField
                Button { presentation.refresh() } label: {
                    Image(systemName: VyronSymbols.refresh)
                }
                .buttonStyle(QuietButtonStyle())
                .help(VyronSkillText.refresh)
                .accessibilityLabel(VyronSkillText.refresh)
                foldersMenu
            }
            Text(VyronSkillText.subtitle)
                .font(VyronPluginsStyle.body)
                .foregroundStyle(palette.muted)
        }
    }

    private var searchField: some View {
        HStack(spacing: VyronPluginsStyle.compactSpacing) {
            Image(systemName: VyronSymbols.search).foregroundStyle(palette.muted)
            TextField(VyronSkillText.search, text: $presentation.searchQuery)
                .textFieldStyle(.plain)
                .accessibilityLabel(VyronSkillText.search)
            if !presentation.searchQuery.isEmpty {
                Button { presentation.searchQuery = "" } label: {
                    Image(systemName: VyronSymbols.close)
                }
                .buttonStyle(.plain)
                .help(VyronPluginText.clearSearch)
                .accessibilityLabel(VyronPluginText.clearSearch)
            }
        }
        .font(VyronPluginsStyle.body)
        .padding(.horizontal, VyronPluginsStyle.rowSpacing)
        .padding(.vertical, VyronPluginsStyle.compactSpacing)
        .frame(maxWidth: VyronPluginsStyle.searchWidth)
        .overlay(Capsule().stroke(palette.border))
    }

    private var foldersMenu: some View {
        Menu {
            ForEach(presentation.roots(projectDirectory: projectDirectory), id: \.directoryURL) { root in
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([root.directoryURL])
                } label: {
                    Text(verbatim: root.directoryURL.path)
                }
                .disabled(!FileManager.default.fileExists(atPath: root.directoryURL.path))
            }
        } label: {
            Image(systemName: VyronSymbols.folder)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(VyronSkillText.folders)
        .accessibilityLabel(VyronSkillText.folders)
    }

    private var catalog: some View {
        VStack(alignment: .leading, spacing: VyronPluginsStyle.sectionSpacing) {
            HStack(spacing: VyronPluginsStyle.compactSpacing) {
                ForEach(VyronSkillFilter.allCases, id: \.self) { filter in
                    Button { presentation.filter = filter } label: {
                        Text(filter.title)
                            .font(VyronPluginsStyle.action)
                            .padding(VyronPluginsStyle.rowSpacing)
                            .background(presentation.filter == filter ? palette.surface : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(presentation.filter == filter ? palette.text : palette.muted)
                    .accessibilityAddTraits(presentation.filter == filter ? .isSelected : [])
                }
                Spacer(minLength: 0)
                if presentation.isLoading {
                    ProgressView().controlSize(.small).help(VyronSkillText.loading)
                }
            }
            if presentation.inventory?.issues.isEmpty == false {
                Label(VyronSkillText.scanWarning, systemImage: VyronSymbols.warning)
                    .font(VyronPluginsStyle.caption)
                    .foregroundStyle(palette.warning)
            }
            if presentation.inventory?.didReachLimit == true {
                Label(VyronSkillText.scanLimit, systemImage: VyronSymbols.details)
                    .font(VyronPluginsStyle.caption)
                    .foregroundStyle(palette.warning)
            }
            if presentation.visibleSkills.isEmpty {
                if !presentation.hasLoadError || presentation.inventory != nil {
                    emptyState
                }
            } else {
                ForEach([VyronSkillScope.personal, .project, .plugin], id: \.self) { scope in
                    let skills = presentation.visibleSkills.filter { $0.scope == scope }
                    if !skills.isEmpty {
                        VStack(alignment: .leading, spacing: VyronPluginsStyle.rowSpacing) {
                            Text(VyronSkillLabels.scope(scope)).font(VyronPluginsStyle.sectionTitle)
                            VyronPluginCatalogGrid {
                                ForEach(skills) { skill in
                                    VyronSkillRow(skill: skill) { presentation.select(skill) }
                                }
                            }
                        }
                    }
                }
            }
            Text(VyronSkillText.browsingNote)
                .font(VyronPluginsStyle.caption)
                .foregroundStyle(palette.muted)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: VyronPluginsStyle.rowSpacing) {
            if presentation.isLoading {
                Text(VyronSkillText.loading)
            } else if presentation.inventory?.skills.isEmpty != false {
                Text(VyronSkillText.emptyTitle).font(VyronPluginsStyle.sectionTitle)
                Text(VyronSkillText.emptyBody).foregroundStyle(palette.muted)
            } else {
                Text(VyronSkillText.noResults).font(VyronPluginsStyle.sectionTitle)
            }
        }
        .font(VyronPluginsStyle.body)
        .padding(.vertical, VyronPluginsStyle.cardPadding)
    }
}
