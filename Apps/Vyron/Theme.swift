import SwiftUI

enum Palette {
    // Codex desktop's packaged default dark theme (26.1027.30824).
    // Neutral controls stay separate from blue tints and semantic status colors.
    static let canvas = rgb(0x181818)
    static let sidebar = rgb(0x141414)
    static let surface = rgb(0x232323)
    static let field = rgb(0x2D2D2D)
    static let raised = rgb(0x363636)
    static let border = Color.white.opacity(0.084)
    static let selection = Color.white.opacity(0.052)
    static let text = rgb(0xDFDFDF)
    static let muted = Color.white.opacity(0.498)
    static let accent = text
    static let onAccent = field
    static let controlAccent = rgb(0x339CFF)
    static let success = rgb(0x40C977)
    static let warning = rgb(0xFF8549)
    static let danger = rgb(0xFF6764)
    static let diffAdded = rgb(0x40C977)
    static let diffRemoved = rgb(0xFA423E)
    static let diffHunk = rgb(0x83C3FF)
    static var diffSyntaxKeyword: Color { VyronColors.diffSyntaxKeyword }
    static var diffSyntaxType: Color { VyronColors.diffSyntaxType }
    static var diffSyntaxName: Color { VyronColors.diffSyntaxName }
    static var diffSyntaxComment: Color { VyronColors.diffSyntaxComment }
    static var diffSyntaxLiteral: Color { VyronColors.diffSyntaxLiteral }
    static let terminal = canvas
    static let codeText = text
    static var effortAccent: Color { VyronColors.effortAccent }
    static var effortTrackStart: Color { VyronColors.effortTrackStart }
    static var effortTrackEnd: Color { VyronColors.effortTrackEnd }
    static var effortTrackMiddle: Color { VyronColors.effortTrackMiddle }
    static var effortTrackInactive: Color { VyronColors.effortTrackInactive }
    static var effortSparkle: Color { VyronColors.effortSparkle }

    private static func rgb(_ value: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(Palette.muted)
    }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    private let foreground: Color

    init(foreground: Color = Palette.muted) {
        self.foreground = foreground
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .padding(7)
            .background(configuration.isPressed ? Palette.raised : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
    }
}

struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Palette.accent.opacity(configuration.isPressed ? 0.7 : 1),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .opacity(isEnabled ? 1 : 0.4)
    }
}

extension Int64 {
    var fileSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
