import SwiftUI
import VyronCore

struct VyronComposerSkillRow: View {
    let command: VyronComposerCommand
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: VyronComposerSkillStyle.rowSpacing) {
                HStack(spacing: VyronComposerSkillStyle.sectionSpacing) {
                    Text(verbatim: command.invocation)
                        .font(VyronComposerSkillStyle.body)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(verbatim: command.scopeLabel)
                        .font(VyronComposerSkillStyle.caption)
                        .foregroundStyle(Palette.muted)
                }
                Text(verbatim: command.description)
                    .font(VyronComposerSkillStyle.caption)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Palette.text)
            .padding(.horizontal, VyronComposerSkillStyle.rowPadding)
            .frame(height: VyronComposerSkillStyle.rowHeight - VyronComposerSkillStyle.rowSpacing)
            .background(isSelected ? Palette.raised : .clear,
                in: RoundedRectangle(cornerRadius: VyronComposerSkillStyle.rowRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(command.help)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
