import AppKit
import SwiftUI
import VyronCore

struct VyronSkillDetailView: View {
    @Environment(\.vyronPalette) private var palette
    let skill: VyronLocalSkill
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VyronPluginsStyle.sectionSpacing) {
            Button(action: back) {
                Label(VyronSkillText.back, systemImage: VyronSymbols.back)
            }
            .buttonStyle(.plain)
            .font(VyronPluginsStyle.action)
            .foregroundStyle(palette.muted)

            HStack(alignment: .top, spacing: VyronPluginsStyle.rowSpacing) {
                VStack(alignment: .leading, spacing: VyronPluginsStyle.rowSpacing) {
                    Text(verbatim: skill.name).font(VyronPluginsStyle.title).textSelection(.enabled)
                    HStack(spacing: VyronPluginsStyle.rowSpacing) {
                        Text(VyronSkillLabels.source(skill.source))
                        Text(VyronSkillLabels.scope(skill.scope))
                    }
                    .font(VyronPluginsStyle.caption)
                    .foregroundStyle(palette.muted)
                }
                Spacer(minLength: 0)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([skill.fileURL])
                } label: {
                    Label(VyronSkillText.reveal, systemImage: VyronSymbols.folder)
                }
                .buttonStyle(QuietButtonStyle())
                .font(VyronPluginsStyle.action)
            }

            Text(verbatim: skill.fileURL.path)
                .font(VyronPluginsStyle.code)
                .foregroundStyle(palette.muted)
                .textSelection(.enabled)
            Text(VyronSkillText.browsingNote)
                .font(VyronPluginsStyle.caption)
                .foregroundStyle(palette.muted)
            if skill.isContentTruncated {
                Label(VyronSkillText.truncated, systemImage: VyronSymbols.details)
                    .font(VyronPluginsStyle.caption)
                    .foregroundStyle(palette.warning)
            }
            Text(verbatim: skill.content)
                .font(VyronPluginsStyle.code)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(VyronPluginsStyle.cardPadding)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: VyronPluginsStyle.cardRadius))
        }
    }
}
