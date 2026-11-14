import SwiftUI

enum VyronAppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: VyronAppearanceText.system
        case .light: VyronAppearanceText.light
        case .dark: VyronAppearanceText.dark
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
