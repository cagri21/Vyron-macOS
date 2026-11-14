import SwiftUI

extension EnvironmentValues {
    var vyronPalette: VyronAppearancePalette {
        get { self[VyronAppearancePaletteKey.self] }
        set { self[VyronAppearancePaletteKey.self] = newValue }
    }
}
