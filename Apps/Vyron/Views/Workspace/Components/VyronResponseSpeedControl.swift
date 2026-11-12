import SwiftUI
import VyronCore

struct VyronResponseSpeedControl: View {
    @Environment(\.locale) private var localizationLocale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var model: AppModel
    @State private var selectionFailed = false

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronEffortStyle.speedDetailSpacing) {
            HStack {
                Text(VyronWorkspaceText.responseSpeed)
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    choice(.standard)
                    choice(.fast)
                }
                .background(Palette.surface, in: Capsule())
                .accessibilityElement(children: .contain)
                .accessibilityLabel(VyronWorkspaceText.responseSpeed)
            }
            Text(selectionFailed ? VyronWorkspaceText.speedChangeFailed : description)
                .font(VyronEffortStyle.speedCaption)
                .foregroundStyle(selectionFailed ? Palette.warning : Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .help(
                    selectionFailed
                        ? model.modelSelection.connectionError ?? VyronWorkspaceText.speedChangeFailed : description
                )
        }
        .font(VyronEffortStyle.control)
        .onChange(of: model.modelSelection.activeConnectionID) { _, _ in selectionFailed = false }
        .onChange(of: model.modelSelection.selectedModel) { _, _ in selectionFailed = false }
    }

    private var description: String {
        guard model.supportsFastResponses else { return VyronWorkspaceText.fastSpeedUnavailable }
        return VyronWorkspaceText.fastSpeedDescription
    }

    private func choice(_ speed: VyronResponseSpeed) -> some View {
        Button {
            selectionFailed = !model.selectResponseSpeed(speed)
        } label: {
            Text(VyronInferenceSelectionPresentation.speedTitle(speed))
                .font(VyronEffortStyle.speedCaption)
                .foregroundStyle(model.responseSpeed == speed ? Palette.text : Palette.muted)
                .padding(.horizontal, VyronEffortStyle.speedButtonHorizontalPadding)
                .padding(.vertical, VyronEffortStyle.speedButtonVerticalPadding)
                .background(selectionColor(speed), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!model.canSelectResponseSpeed || speed == .fast && !model.supportsFastResponses)
        .accessibilityAddTraits(model.responseSpeed == speed ? .isSelected : [])
        .animation(reduceMotion ? nil : VyronEffortStyle.selectionAnimation, value: model.responseSpeed)
        .help(speed == .fast ? VyronWorkspaceText.fastSpeedDescription : VyronWorkspaceText.standardSpeedDescription)
    }

    private func selectionColor(_ speed: VyronResponseSpeed) -> Color {
        guard model.responseSpeed == speed else { return .clear }
        return speed == .fast ? Palette.effortAccent.opacity(VyronEffortStyle.speedSelectedOpacity) : Palette.raised
    }
}
