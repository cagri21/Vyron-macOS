import SwiftUI

struct VyronAppearanceVariants: Codable, Equatable, Sendable {
    var light = VyronAppearanceColorOverrides()
    var dark = VyronAppearanceColorOverrides()

    var isEmpty: Bool { light.isEmpty && dark.isEmpty }

    subscript(scheme: ColorScheme) -> VyronAppearanceColorOverrides {
        get { scheme == .dark ? dark : light }
        set {
            if scheme == .dark {
                dark = newValue
            } else {
                light = newValue
            }
        }
    }
}
