import SwiftUI

struct VyronSidebarRowBackground: ViewModifier {
    @Environment(\.vyronPalette) private var palette
    var isSelected = false
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                isSelected ? palette.raised : isHovered ? palette.selection : Color.clear,
                in: RoundedRectangle(cornerRadius: VyronSidebarStyle.rowRadius)
            )
            .onHover { isHovered = $0 }
    }
}
