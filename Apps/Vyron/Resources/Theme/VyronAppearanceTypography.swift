import AppKit
import SwiftUI

struct VyronAppearanceTypography {
    static let body = Self(size: 13)

    let size: CGFloat
    private let fontWeight: Font.Weight

    init(size: CGFloat, weight: Font.Weight = .regular) {
        self.size = size
        fontWeight = weight
    }

    func weight(_ weight: Font.Weight) -> Self {
        Self(size: size, weight: weight)
    }

    @MainActor
    func font(family: String?) -> Font {
        if let family, let face = NSFontManager.shared.font(
            withFamily: family, traits: [], weight: 5, size: size
        ) {
            return .custom(face.fontName, fixedSize: size).weight(fontWeight)
        }
        return .system(size: size, weight: fontWeight)
    }
}
