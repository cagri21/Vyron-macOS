import SwiftUI

struct VyronWorkspaceHeaderIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(VyronWorkspaceHeaderStyle.icon)
            .foregroundStyle(Palette.text)
            .frame(width: VyronWorkspaceHeaderStyle.controlSize, height: VyronWorkspaceHeaderStyle.controlSize)
            .contentShape(Rectangle())
    }
}
