import SwiftUI

struct VyronSettingsSidebar: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @Binding var search: String
    let matchingSections: [VyronSettingsSection]

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronSettingsStyle.sidebarSectionSpacing) {
            VStack(alignment: .leading, spacing: VyronSettingsStyle.headingSpacing) {
                Text(VyronSidebarText.settings)
                    .font(VyronSettingsStyle.sidebarTitle)
                    .foregroundStyle(Palette.text)
                searchField
            }
            ScrollView {
                VStack(alignment: .leading, spacing: VyronSettingsStyle.sidebarSectionSpacing) {
                    group(VyronSettingsText.personal, sections: [.general, .voice])
                    group(VyronSettingsText.integrations, sections: [.models, .billing, .plugins, .macControls])
                    if matchingSections.isEmpty {
                        Text(VyronSettingsText.noResults)
                            .font(VyronSettingsStyle.detail)
                            .foregroundStyle(Palette.muted)
                            .padding(.horizontal, VyronSettingsStyle.searchInset)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, VyronSettingsStyle.sidebarPadding)
        .padding(.top, VyronSettingsStyle.sidebarTopPadding)
        .frame(width: VyronSettingsStyle.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.surface)
    }

    private var searchField: some View {
        HStack(spacing: VyronSettingsStyle.textSpacing) {
            Image(systemName: VyronSymbols.search)
                .font(VyronSettingsStyle.detail)
                .accessibilityHidden(true)
            TextField(VyronSettingsText.search, text: $search)
                .textFieldStyle(.plain)
                .font(VyronSettingsStyle.body)
                .accessibilityLabel(VyronSettingsText.search)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: VyronSymbols.searchClear)
                }
                .buttonStyle(.plain)
                .help(VyronSidebarText.clearSearch)
                .accessibilityLabel(VyronSidebarText.clearSearch)
            }
        }
        .foregroundStyle(Palette.muted)
        .padding(.horizontal, VyronSettingsStyle.searchInset)
        .frame(height: VyronSettingsStyle.searchHeight)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: VyronSettingsStyle.searchRadius))
    }

    @ViewBuilder
    private func group(_ title: String, sections: [VyronSettingsSection]) -> some View {
        let visible = sections.filter { matchingSections.contains($0) }
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: VyronSettingsStyle.textSpacing) {
                Text(verbatim: title)
                    .font(VyronSettingsStyle.body)
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, VyronSettingsStyle.searchInset)
                VStack(spacing: VyronSettingsStyle.sidebarRowSpacing) {
                    ForEach(visible) { section in
                        Button {
                            model.appNavigation.settingsSection = section
                        } label: {
                            HStack(spacing: VyronSettingsStyle.searchInset) {
                                Image(systemName: section.symbol)
                                    .font(VyronSettingsStyle.sidebarIcon)
                                    .frame(width: VyronSettingsStyle.sidebarIconWidth)
                                    .accessibilityHidden(true)
                                Text(verbatim: section.title)
                                    .font(VyronSettingsStyle.body)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(Palette.text)
                            .padding(.horizontal, VyronSettingsStyle.searchInset)
                            .frame(minHeight: VyronSettingsStyle.sidebarRowHeight)
                            .background(
                                model.appNavigation.settingsSection == section ? Palette.raised : Color.clear,
                                in: RoundedRectangle(cornerRadius: VyronSettingsStyle.rowRadius)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(model.appNavigation.settingsSection == section ? .isSelected : [])
                    }
                }
            }
        }
    }
}
