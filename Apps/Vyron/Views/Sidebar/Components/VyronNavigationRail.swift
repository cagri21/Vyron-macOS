import SwiftUI

struct VyronNavigationRail: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    let showsNewTask: Bool

    var body: some View {
        let _ = localizationLocale
        VStack(spacing: VyronSidebarStyle.railSpacing) {
            railButton(
                VyronSidebarText.home,
                symbol: VyronSymbols.home,
                selected: model.appNavigation.destination == .workspace
            ) {
                model.returnToWorkspace()
            }
            if showsNewTask {
                railButton(VyronSidebarText.newTask, symbol: VyronSymbols.newTask) {
                    model.requestNewTask()
                }
            }
            railButton(
                VyronScheduledTaskText.scheduledTasks,
                symbol: VyronSymbols.clock,
                selected: model.appNavigation.showScheduledTasks
            ) {
                model.appNavigation.showScheduledTasks = true
            }
            railButton(
                VyronPluginText.title,
                symbol: VyronSymbols.plugins,
                selected: model.appNavigation.destination == .plugins
            ) {
                model.openPlugins()
            }
            advancedTools
            Spacer(minLength: 0)
            if model.modelDownloads.isActive {
                ProgressView().controlSize(.small)
                    .frame(width: VyronSidebarStyle.railButtonSize, height: VyronSidebarStyle.railButtonSize)
                    .help(model.modelDownloads.active?.tag ?? VyronSidebarText.manageModels)
                    .accessibilityLabel(VyronSidebarText.manageModels)
            }
            railButton(VyronSidebarText.manageModels, symbol: VyronSymbols.model) {
                model.appNavigation.showSetup = true
            }
            railButton(
                VyronSidebarText.settings,
                symbol: VyronSymbols.settings,
                selected: model.appNavigation.destination == .settings
            ) {
                model.openSettings()
            }
            .accessibilityValue(model.modelSelection.connectionLabel)
        }
        .padding(.top, VyronSidebarStyle.railTopInset)
        .padding(.bottom, VyronSidebarStyle.railBottomInset)
        .frame(width: VyronSidebarStyle.railWidth)
        .background(VyronSidebarStyle.railBackground)
    }

    private func railButton(
        _ title: String,
        symbol: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(VyronSidebarStyle.railIconFont)
                .foregroundStyle(selected ? Palette.text : Palette.text.opacity(0.7))
                .frame(width: VyronSidebarStyle.railButtonSize, height: VyronSidebarStyle.railButtonSize)
                .background(
                    selected ? Palette.selection : Color.clear,
                    in: RoundedRectangle(cornerRadius: VyronSidebarStyle.rowRadius)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(VyronSidebarRowBackground())
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var advancedTools: some View {
        Menu {
            Button(VyronSidebarText.macControls) { model.appNavigation.showAutomation = true }
            Button(VyronSidebarText.manageModels) { model.appNavigation.showSetup = true }
            Button(VyronPluginText.title) { model.openPlugins() }
        } label: {
            Image(systemName: VyronSymbols.ellipsis)
                .font(VyronSidebarStyle.railMenuFont)
                .foregroundStyle(Palette.text)
                .frame(width: VyronSidebarStyle.railButtonSize, height: VyronSidebarStyle.railButtonSize)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(Palette.text)
        .font(VyronSidebarStyle.railMenuFont)
        .fixedSize()
        .modifier(VyronSidebarRowBackground())
        .help(VyronSidebarText.advancedTools)
        .accessibilityLabel(VyronSidebarText.advancedTools)
    }
}
