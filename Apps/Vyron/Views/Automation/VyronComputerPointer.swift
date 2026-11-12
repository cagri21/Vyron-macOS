import SwiftUI

struct VyronComputerPointer: View {
    var body: some View {
        Image(systemName: VyronSymbols.computerClick)
            .font(VyronComputerPreviewStyle.pointerFont)
            .foregroundStyle(Palette.controlAccent)
            .frame(width: VyronComputerPreviewStyle.pointerSize, height: VyronComputerPreviewStyle.pointerSize)
            .background(Palette.canvas, in: Circle())
            .overlay { Circle().strokeBorder(Palette.controlAccent, lineWidth: VyronComputerPreviewStyle.pointerOutline) }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
