import AppKit
import SwiftUI

struct VyronAppearanceColor: Codable, Equatable, Sendable {
    private static let hexLength = 6
    private static let channelMask: UInt32 = 0xFF
    private static let channelMaximum = Double(channelMask)
    private static let minimumStatusContrast = 4.5
    private let packed: UInt32

    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.first == "#" ? trimmed.dropFirst() : trimmed[...]
        guard digits.utf8.count == Self.hexLength,
              digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let packed = UInt32(digits, radix: 16)
        else { return nil }
        self.packed = packed
    }

    init?(color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let components = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        guard components.allSatisfy(\.isFinite) else { return nil }
        packed = components.reduce(UInt32.zero) { value, component in
            let normalized = min(1, max(0, Double(component)))
            return (value << 8) | UInt32((normalized * Self.channelMaximum).rounded())
        }
    }

    var hex: String { String(format: "#%06X", packed) }

    var color: Color {
        Color(.sRGB, red: channel(16), green: channel(8), blue: channel(0), opacity: 1)
    }

    var contrastingText: Color {
        let blackContrast = (luminance + 0.05) / 0.05
        let whiteContrast = 1.05 / (luminance + 0.05)
        return blackContrast >= whiteContrast ? .black : .white
    }

    func contrastRatio(over surface: Self) -> Double {
        let ink = luminance
        let background = surface.luminance
        return (max(ink, background) + 0.05) / (min(ink, background) + 0.05)
    }

    func legible(over surface: Self) -> Color {
        guard contrastRatio(over: surface) < Self.minimumStatusContrast else { return color }
        let highContrast = surface.contrastingText
        guard let target = Self(color: highContrast) else { return highContrast }
        for adjustment in [0.125, 0.25, 0.5, 0.75] {
            let candidate = mixed(with: target, amount: adjustment)
            if let adjusted = Self(color: candidate), adjusted.contrastRatio(over: surface) >= Self.minimumStatusContrast {
                return candidate
            }
        }
        return highContrast
    }

    func mixed(with other: Self, amount: Double) -> Color {
        let retained = 1 - amount
        return Color(
            .sRGB,
            red: channel(16) * retained + other.channel(16) * amount,
            green: channel(8) * retained + other.channel(8) * amount,
            blue: channel(0) * retained + other.channel(0) * amount,
            opacity: 1
        )
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hex = try container.decode(String.self)
        guard let parsed = Self(hex: hex) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a six-digit sRGB color.")
        }
        self = parsed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }

    private func channel(_ shift: UInt32) -> Double {
        Double((packed >> shift) & Self.channelMask) / Self.channelMaximum
    }

    private var luminance: Double {
        0.2126 * linear(channel(16)) + 0.7152 * linear(channel(8)) + 0.0722 * linear(channel(0))
    }

    private func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
}
