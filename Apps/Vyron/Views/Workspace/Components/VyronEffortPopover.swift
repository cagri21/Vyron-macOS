import SwiftUI

struct VyronEffortPopover: View {
    @Environment(\.locale) private var localizationLocale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let _ = localizationLocale
        VStack(spacing: VyronEffortStyle.sectionSpacing) {
            VStack(spacing: 0) {
                header
                VyronComposerModelMenu(isCompact: true)
                    .frame(height: VyronEffortStyle.subtitleHeight)
            }
            VyronEffortSlider()
                .disabled(!model.canSelectDevelopmentEffort)
            VyronResponseSpeedControl()
        }
        .padding(VyronEffortStyle.popoverPadding)
        .frame(width: VyronEffortStyle.popoverWidth)
        .background(Palette.field, in: RoundedRectangle(cornerRadius: VyronEffortStyle.popoverRadius))
    }

    private var header: some View {
        ZStack {
            Text(VyronEffortPresentation.title(model.composer.effort))
                .font(VyronEffortStyle.title)
                .foregroundStyle(Palette.effortAccent)
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : VyronEffortStyle.selectionAnimation, value: model.composer.effort)
                .padding(.horizontal, VyronEffortStyle.headerTitleInset)
                .help(VyronEffortPresentation.description(model.composer.effort))
                .accessibilityHint(VyronEffortPresentation.description(model.composer.effort))
            HStack {
                Image(systemName: VyronSymbols.model)
                    .foregroundStyle(Palette.effortAccent)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Button {
                    model.selectDevelopmentEffort(.automatic)
                } label: {
                    Image(systemName: VyronSymbols.effortReset)
                        .foregroundStyle(Palette.muted)
                        .frame(width: VyronEffortStyle.headerIconSize, height: VyronEffortStyle.headerHeight)
                }
                .buttonStyle(.plain)
                .disabled(!model.canSelectDevelopmentEffort)
                .help(VyronWorkspaceText.resetEffort)
                .accessibilityLabel(VyronWorkspaceText.resetEffort)
                .accessibilityHint(VyronEffortPresentation.description(.automatic))
            }
            .font(VyronEffortStyle.icon)
        }
        .frame(height: VyronEffortStyle.headerHeight)
    }
}
