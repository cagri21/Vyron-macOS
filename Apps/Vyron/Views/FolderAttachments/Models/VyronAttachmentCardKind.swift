import SwiftUI

enum VyronAttachmentCardKind {
    case pdf
    case image(VyronImageFileExtension)

    var typeLabel: String {
        switch self {
        case .pdf: "PDF"
        case .image(let fileExtension): fileExtension.value
        }
    }

    func tint(in palette: VyronAppearancePalette) -> Color {
        switch self {
        case .pdf: palette.diffRemoved
        case .image: palette.controlAccent
        }
    }

    var symbol: String {
        switch self {
        case .pdf: VyronSymbols.attachmentDocument
        case .image: VyronSymbols.screenshot
        }
    }
}
