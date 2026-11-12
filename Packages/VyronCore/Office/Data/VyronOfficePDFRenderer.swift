import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VyronDevelopment

enum VyronOfficePDFRenderer {
    static func render(_ data: Data, pages requestedPages: [Int]) throws -> [VyronOfficeArtifact] {
        try Task.checkCancellation()
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
            !document.isEncrypted, document.numberOfPages > 0 else {
            throw VyronOfficeError(message: "Choose a readable, unencrypted PDF for local page previews.")
        }
        let pages = requestedPages.isEmpty
            ? Array(1...min(document.numberOfPages, VyronOfficeLimits.defaultPreviewPages)) : requestedPages
        guard pages.count <= VyronOfficeLimits.maximumPages, Set(pages).count == pages.count,
            pages.allSatisfy({ $0 >= 1 && $0 <= document.numberOfPages }) else {
            throw VyronOfficeError(message: "Choose existing PDF page numbers, at most 20 per render.")
        }
        var totalBytes = 0
        return try pages.map { number in
            try Task.checkCancellation()
            guard let page = document.page(at: number) else { throw failed() }
            let box = page.getBoxRect(.cropBox)
            let size = try dimensions(for: box)
            let width = size.width
            let height = size.height
            guard let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { throw failed() }
            let rectangle = CGRect(x: 0, y: 0, width: width, height: height)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(rectangle)
            context.concatenate(page.getDrawingTransform(.cropBox, rect: rectangle, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
            try Task.checkCancellation()
            let output = NSMutableData()
            guard let image = context.makeImage(),
                let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
            else { throw failed() }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw failed() }
            totalBytes += output.length
            guard totalBytes <= VyronOfficeLimits.maximumOutputBytes else { throw failed() }
            return VyronOfficeArtifact(name: String(format: "page-%04d.png", number), data: output as Data)
        }
    }

    static func dimensions(for box: CGRect) throws -> VyronOfficePageSize {
        guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else { throw failed() }
        let scale = min(
            Double(VyronOfficeLimits.previewWidth) / box.width,
            Double(VyronOfficeLimits.maximumPageDimension) / box.height
        )
        let width = (box.width * scale).rounded(.up)
        let height = (box.height * scale).rounded(.up)
        guard scale.isFinite, width.isFinite, height.isFinite, width >= 0, height >= 0,
            width <= Double(VyronOfficeLimits.maximumPageDimension),
            height <= Double(VyronOfficeLimits.maximumPageDimension) else { throw failed() }
        return VyronOfficePageSize(width: max(1, Int(width)), height: max(1, Int(height)))
    }

    private static func failed() -> VyronOfficeError {
        VyronOfficeError(message: "The PDF page could not be rendered within the local preview limits.")
    }
}
