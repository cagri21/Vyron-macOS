import SwiftUI

struct VyronComposerSkillChip: View {
    @Environment(\.vyronPalette) private var palette
    let mention: VyronComposerSkillMention
    let remove: () -> Void

    var body: some View {
        Button(action: remove) {
            HStack(spacing: VyronComposerSkillStyle.mentionSpacing) {
                Image(systemName: VyronSymbols.skills)
                Text(verbatim: mention.label)
                    .lineLimit(1)
                    .frame(maxWidth: VyronComposerSkillStyle.mentionLabelMaximumWidth, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: VyronSymbols.close)
                    .font(VyronComposerSkillStyle.caption)
                    .accessibilityHidden(true)
            }
            .font(VyronComposerSkillStyle.body)
            .foregroundStyle(palette.controlAccent)
            .padding(.horizontal, VyronComposerSkillStyle.mentionHorizontalPadding)
            .padding(.vertical, VyronComposerSkillStyle.mentionVerticalPadding)
            .background(palette.surface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: mention.label))
        .accessibilityHint(VyronToolsText.remove)
        .help(mention.command.skill.fileURL.path)
    }
}
