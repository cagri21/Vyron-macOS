import SwiftUI
import VyronCore

struct VyronSkillRow: View {
    @Environment(\.vyronPalette) private var palette
    let skill: VyronLocalSkill
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: VyronPluginsStyle.rowSpacing) {
                Image(systemName: VyronSymbols.skills)
                    .font(.system(size: VyronPluginsStyle.iconGlyphSize))
                    .frame(width: VyronPluginsStyle.iconSize, height: VyronPluginsStyle.iconSize)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: VyronPluginsStyle.rowRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: VyronPluginsStyle.rowRadius).stroke(palette.border)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: VyronPluginsStyle.compactSpacing) {
                    HStack(spacing: VyronPluginsStyle.compactSpacing) {
                        Text(verbatim: skill.name)
                            .font(VyronPluginsStyle.body)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(VyronSkillLabels.source(skill.source))
                            .font(VyronPluginsStyle.caption)
                            .foregroundStyle(palette.muted)
                    }
                    if !skill.description.isEmpty {
                        Text(verbatim: skill.description)
                            .font(VyronPluginsStyle.body)
                            .foregroundStyle(palette.muted)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Image(systemName: VyronSymbols.chevronRight)
                    .font(VyronPluginsStyle.caption)
                    .foregroundStyle(palette.muted)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(palette.text)
            .padding(.vertical, VyronPluginsStyle.rowSpacing)
            .frame(maxWidth: .infinity, minHeight: VyronPluginsStyle.minimumRowHeight, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(skill.fileURL.path)
    }
}
