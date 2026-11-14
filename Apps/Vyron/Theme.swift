import SwiftUI

enum Palette {
    // The baseline used by visual test fixtures without an injected appearance.
    static var canvas: Color { VyronAppearancePalette.default.canvas }
    static var surface: Color { VyronAppearancePalette.default.surface }
    static var raised: Color { VyronAppearancePalette.default.raised }
    static var text: Color { VyronAppearancePalette.default.text }

    static var diffSyntaxKeyword: Color { VyronColors.diffSyntaxKeyword }
    static var diffSyntaxType: Color { VyronColors.diffSyntaxType }
    static var diffSyntaxName: Color { VyronColors.diffSyntaxName }
    static var diffSyntaxComment: Color { VyronColors.diffSyntaxComment }
    static var diffSyntaxLiteral: Color { VyronColors.diffSyntaxLiteral }
    static var effortAccent: Color { VyronColors.effortAccent }
    static var effortTrackStart: Color { VyronColors.effortTrackStart }
    static var effortTrackEnd: Color { VyronColors.effortTrackEnd }
    static var effortTrackMiddle: Color { VyronColors.effortTrackMiddle }
    static var effortTrackInactive: Color { VyronColors.effortTrackInactive }
    static var effortSparkle: Color { VyronColors.effortSparkle }
}
