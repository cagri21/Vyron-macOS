import SwiftUI

enum VyronDiffSyntaxRole {
    case comment
    case keyword
    case literal
    case name
    case type

    func color(for scheme: ColorScheme) -> Color {
        switch self {
        case .comment:
            scheme == .light ? VyronColors.appearanceLightDiffSyntaxComment : VyronColors.diffSyntaxComment
        case .keyword:
            scheme == .light ? VyronColors.appearanceLightDiffSyntaxKeyword : VyronColors.diffSyntaxKeyword
        case .literal:
            scheme == .light ? VyronColors.appearanceLightDiffSyntaxLiteral : VyronColors.diffSyntaxLiteral
        case .name:
            scheme == .light ? VyronColors.appearanceLightDiffSyntaxName : VyronColors.diffSyntaxName
        case .type:
            scheme == .light ? VyronColors.appearanceLightDiffSyntaxType : VyronColors.diffSyntaxType
        }
    }
}
