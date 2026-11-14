import Foundation

struct VyronAppearanceShare: Codable, Sendable {
    static let currentVersion = 1
    static let maximumBytes = 4_096
    private static let maximumFontBytes = 256

    let version: Int
    let preset: VyronAppearancePreset
    let colors: VyronAppearanceVariants
    let fontFamily: String?

    var isSupported: Bool {
        guard version == Self.currentVersion else { return false }
        guard let fontFamily else { return true }
        let trimmed = fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == fontFamily &&
            fontFamily.utf8.count <= Self.maximumFontBytes &&
            fontFamily.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
}
