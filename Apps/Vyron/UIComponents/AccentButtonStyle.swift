import SwiftUI

struct AccentButtonStyle: ButtonStyle {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                palette.accent.opacity(configuration.isPressed ? 0.7 : 1),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}
