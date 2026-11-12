import SwiftUI

struct VyronSidebarRowBackground: ViewModifier {
    var isSelected = false
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                isSelected ? VyronSidebarStyle.selection : isHovered ? VyronSidebarStyle.hover : Color.clear,
                in: RoundedRectangle(cornerRadius: VyronSidebarStyle.rowRadius)
            )
            .onHover { isHovered = $0 }
    }
}
