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

    var tint: Color {
        switch self {
        case .pdf: Palette.diffRemoved
        case .image: Palette.controlAccent
        }
    }

    var symbol: String {
        switch self {
        case .pdf: VyronSymbols.attachmentDocument
        case .image: VyronSymbols.screenshot
        }
    }
}
