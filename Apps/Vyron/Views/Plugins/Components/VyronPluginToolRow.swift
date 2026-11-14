import SwiftUI
import VyronCore

struct VyronPluginToolRow: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    let tool: MCPTool
    let canReviewWrites: Bool

    var body: some View {
        let _ = localizationLocale
        HStack(alignment: .top, spacing: VyronPluginsStyle.rowSpacing) {
            Image(systemName: tool.isReadOnly ? VyronSymbols.eye : VyronSymbols.pencil)
                .foregroundStyle(palette.muted)
            VStack(alignment: .leading, spacing: VyronPluginsStyle.compactSpacing) {
                Text(verbatim: tool.name).font(VyronPluginsStyle.code).textSelection(.enabled)
                if let description = tool.description {
                    Text(verbatim: description).font(VyronPluginsStyle.caption)
                        .foregroundStyle(palette.muted).lineLimit(4).textSelection(.enabled)
                }
                Text(accessDescription)
                    .font(VyronPluginsStyle.caption).foregroundStyle(palette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, VyronPluginsStyle.compactSpacing)
    }

    private var accessDescription: String {
        if tool.isReadOnly { return VyronPluginText.serverReadOnly }
        return canReviewWrites ? VyronPluginText.writeReview : VyronPluginText.unavailableReadOnly
    }
}
