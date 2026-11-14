import SwiftUI

struct VyronWorkspaceHeaderIcon: View {
    @Environment(\.vyronPalette) private var palette
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(VyronWorkspaceHeaderStyle.icon)
            .foregroundStyle(palette.text)
            .frame(width: VyronWorkspaceHeaderStyle.controlSize, height: VyronWorkspaceHeaderStyle.controlSize)
            .contentShape(Rectangle())
    }
}
