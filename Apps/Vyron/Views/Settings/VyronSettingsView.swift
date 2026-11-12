import SwiftUI

struct VyronSettingsView: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @State private var search = ""

    private var matchingSections: [VyronSettingsSection] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return VyronSettingsSection.allCases }
        return VyronSettingsSection.allCases.filter { section in
            ([section.title] + section.searchTerms).contains { $0.localizedStandardContains(query) }
        }
    }

    var body: some View {
        let _ = localizationLocale
        HStack(spacing: 0) {
            VyronSettingsSidebar(search: $search, matchingSections: matchingSections)
            Rectangle().fill(Palette.border).frame(width: VyronSettingsStyle.dividerWidth)
            VStack(alignment: .leading, spacing: 0) {
                Text(matchingSections.isEmpty ? VyronSettingsText.search : model.appNavigation.settingsSection.title)
                    .font(VyronSettingsStyle.title)
                    .foregroundStyle(Palette.text)
                    .frame(maxWidth: VyronSettingsStyle.contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, VyronSettingsStyle.contentPadding)
                    .padding(.top, VyronSettingsStyle.contentTopPadding)
                    .padding(.bottom, VyronSettingsStyle.sectionSpacing)
                detail
            }
            .frame(minWidth: VyronSettingsStyle.minimumContentWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: VyronSettingsStyle.minimumWidth, minHeight: VyronSettingsStyle.minimumHeight)
        .background(Palette.canvas)
        .tint(Palette.controlAccent)
        .onChange(of: search) { _, _ in
            if !matchingSections.contains(model.appNavigation.settingsSection), let first = matchingSections.first {
                model.appNavigation.settingsSection = first
            }
        }
        .onChange(of: model.appNavigation.settingsSection) { _, section in
            if !matchingSections.contains(section) {
                search = ""
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if matchingSections.isEmpty {
            Text(VyronSettingsText.noResults)
                .font(VyronSettingsStyle.body)
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, VyronSettingsStyle.contentPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if model.appNavigation.settingsSection == .models {
            SetupView(downloads: model.modelDownloads, selection: model.modelSelection, showsHeader: false)
                .padding(.horizontal, VyronSettingsStyle.contentPadding)
                .padding(.bottom, VyronSettingsStyle.contentPadding)
        } else if model.appNavigation.settingsSection == .billing {
            VyronBillingSettingsView()
        } else {
            ScrollView {
                sectionContent
                    .frame(maxWidth: VyronSettingsStyle.contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, VyronSettingsStyle.contentPadding)
                    .padding(.bottom, VyronSettingsStyle.contentPadding)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch model.appNavigation.settingsSection {
        case .general:
            VyronGeneralSettingsView()
        case .voice:
            VyronVoiceSettingsView(voice: model.voice)
        case .models:
            EmptyView()
        case .billing:
            EmptyView()
        case .plugins:
            VyronIntegrationSettingsView(connections: model.mcpConnections)
        case .macControls:
            VyronMacControlSettingsView()
        }
    }
}
