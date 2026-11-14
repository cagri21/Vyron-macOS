import SwiftUI

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    private let foreground: Color?

    init(foreground: Color? = nil) {
        self.foreground = foreground
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground ?? palette.muted)
            .padding(7)
            .background(configuration.isPressed ? palette.raised : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
    }
}
