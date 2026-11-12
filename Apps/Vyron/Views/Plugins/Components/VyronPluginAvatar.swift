import SwiftUI

struct VyronPluginAvatar: View {
    let isPenpot: Bool
    var compact = false

    var body: some View {
        Image(systemName: isPenpot ? VyronSymbols.penpot : VyronSymbols.server)
            .font(.system(size: compact ? VyronPluginsStyle.sidebarGlyphSize : VyronPluginsStyle.iconGlyphSize))
            .foregroundStyle(Palette.text)
            .frame(
                width: compact ? VyronPluginsStyle.sidebarIconSize : VyronPluginsStyle.iconSize,
                height: compact ? VyronPluginsStyle.sidebarIconSize : VyronPluginsStyle.iconSize
            )
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: VyronPluginsStyle.rowRadius))
            .accessibilityHidden(true)
    }
}
