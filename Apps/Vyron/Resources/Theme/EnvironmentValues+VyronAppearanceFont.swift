import SwiftUI

extension EnvironmentValues {
    var vyronAppearanceFontFamily: String? {
        get { self[VyronAppearanceFontFamilyKey.self] }
        set { self[VyronAppearanceFontFamilyKey.self] = newValue }
    }
}
