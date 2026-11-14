import SwiftUI

struct VyronPluginAvatar: View {
    @Environment(\.vyronPalette) private var palette
    let isPenpot: Bool
    var compact = false

    var body: some View {
        Image(systemName: isPenpot ? VyronSymbols.penpot : VyronSymbols.server)
            .font(.system(size: compact ? VyronPluginsStyle.sidebarGlyphSize : VyronPluginsStyle.iconGlyphSize))
            .foregroundStyle(palette.text)
            .frame(
                width: compact ? VyronPluginsStyle.sidebarIconSize : VyronPluginsStyle.iconSize,
                height: compact ? VyronPluginsStyle.sidebarIconSize : VyronPluginsStyle.iconSize
            )
            .background(palette.raised, in: RoundedRectangle(cornerRadius: VyronPluginsStyle.rowRadius))
            .accessibilityHidden(true)
    }
}
