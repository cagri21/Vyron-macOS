import SwiftUI

struct VyronComputerPointer: View {
    @Environment(\.vyronPalette) private var palette
    var body: some View {
        Image(systemName: VyronSymbols.computerClick)
            .font(VyronComputerPreviewStyle.pointerFont)
            .foregroundStyle(palette.controlAccent)
            .frame(width: VyronComputerPreviewStyle.pointerSize, height: VyronComputerPreviewStyle.pointerSize)
            .background(palette.canvas, in: Circle())
            .overlay { Circle().strokeBorder(palette.controlAccent, lineWidth: VyronComputerPreviewStyle.pointerOutline) }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
