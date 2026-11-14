import SwiftUI

struct Eyebrow: View {
    @Environment(\.vyronPalette) private var palette
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(palette.muted)
    }
}
