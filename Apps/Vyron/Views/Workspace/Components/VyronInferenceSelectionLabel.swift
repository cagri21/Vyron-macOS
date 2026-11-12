import SwiftUI
import VyronCore

struct VyronInferenceSelectionLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let modelName: String
    let effort: AgentEffort
    let speed: VyronResponseSpeed
    let expanded: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            label.fixedSize(horizontal: true, vertical: false)
            label.frame(maxWidth: VyronEffortStyle.controlMaximumWidth)
        }
        .animation(reduceMotion ? nil : VyronEffortStyle.selectionAnimation, value: effort)
        .animation(reduceMotion ? nil : VyronEffortStyle.selectionAnimation, value: speed)
        .animation(reduceMotion ? nil : VyronEffortStyle.selectionAnimation, value: expanded)
    }

    private var label: some View {
        HStack(spacing: VyronEffortStyle.controlSpacing) {
            Image(systemName: VyronSymbols.model)
                .foregroundStyle(Palette.text)
                .accessibilityHidden(true)
            Text(verbatim: modelName)
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1)
            Text(VyronEffortPresentation.title(effort))
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.opacity)
            if speed == .fast {
                Text(VyronWorkspaceText.fastSpeed)
                    .foregroundStyle(Palette.effortAccent)
                    .fixedSize()
                    .transition(.opacity)
            }
            Image(systemName: VyronSymbols.chevronDown)
                .font(VyronEffortStyle.chevron)
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .accessibilityHidden(true)
        }
        .font(VyronEffortStyle.control)
        .foregroundStyle(Palette.muted)
        .padding(.horizontal, VyronEffortStyle.controlPadding)
        .frame(height: VyronEffortStyle.controlHeight)
        .background(Palette.field, in: Capsule())
        .contentShape(Capsule())
    }
}
