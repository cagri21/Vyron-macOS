import SwiftUI

struct VyronComposerDropTarget: ViewModifier {
    @Environment(\.vyronPalette) private var palette
    @EnvironmentObject private var model: AppModel
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onDrop(of: VyronComposerDropLoader.contentTypes, isTargeted: $isTargeted) { providers in
                model.acceptComposerDrop(providers)
            }
            .overlay {
                if isTargeted && model.canAcceptComposerDrop {
                    RoundedRectangle(cornerRadius: VyronWorkspaceStyle.composerRadius)
                        .stroke(palette.accent, lineWidth: VyronWorkspaceStyle.dividerWidth)
                        .allowsHitTesting(false)
                }
            }
    }
}
