import CoreGraphics
import Darwin
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import VyronModelDomain

actor VyronPDFAttachmentLoader {
    func load(_ url: URL) throws -> VyronPDFAttachment {
        try Task.checkCancellation()
        guard url.isFileURL else { throw VyronPDFAttachmentError.unreadable }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw VyronPDFAttachmentError.unreadable }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw VyronPDFAttachmentError.unreadable
        }
        guard info.st_size <= VyronPDFAttachmentLimits.maximumImportBytes
        else { throw VyronPDFAttachmentError.tooLarge }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data = try file.read(upToCount: VyronPDFAttachmentLimits.maximumImportBytes + 1)
        guard let data else { throw VyronPDFAttachmentError.unreadable }
        return try load(data, name: url.lastPathComponent)
    }

    func load(_ data: Data, name: String) throws -> VyronPDFAttachment {
        try Task.checkCancellation()
        guard data.count <= VyronPDFAttachmentLimits.maximumImportBytes else { throw VyronPDFAttachmentError.tooLarge }
        guard let document = PDFDocument(data: data), !document.isLocked,
            document.allowsCopying, let firstPage = document.page(at: 0)
        else { throw VyronPDFAttachmentError.unreadable }
        let pageLimit = min(document.pageCount, VyronPDFAttachmentLimits.maximumExtractedPages)
        var text = ""
        var remainingBytes = VyronPDFAttachmentLimits.maximumTextBytes
        var isTruncated = document.pageCount > pageLimit
        for index in 0..<pageLimit {
            try Task.checkCancellation()
            guard let page = document.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                !page.isEmpty else { continue }
            let separator = text.isEmpty ? "" : "\n\n"
            let allowance = max(0, remainingBytes - separator.utf8.count)
            let excerpt = boundedAgentPrefix(page, bytes: allowance)
            if !excerpt.isEmpty {
                text += separator + excerpt
                remainingBytes -= separator.utf8.count + excerpt.utf8.count
            }
            if excerpt != page {
                isTruncated = true
                break
            }
        }
        guard !text.isEmpty else { throw VyronPDFAttachmentError.noText }
        try Task.checkCancellation()
        let preview = VyronPDFPreview(name: name, imageData: firstPage.pageRef.flatMap(thumbnail))
        try Task.checkCancellation()
        return VyronPDFAttachment(preview: preview, text: text, isTruncated: isTruncated)
    }

    private func thumbnail(_ page: CGPDFPage) -> Data? {
        let crop = page.getBoxRect(.cropBox)
        guard crop.width.isFinite, crop.height.isFinite, crop.width > 0, crop.height > 0 else { return nil }
        let rotated = page.rotationAngle % 180 != 0
        let size = rotated ? CGSize(width: crop.height, height: crop.width) : crop.size
        let largest = max(size.width, size.height)
        let maximumDimension = CGFloat(VyronPDFAttachmentLimits.thumbnailMaximumDimension)
        let width = max(1, Int((size.width / largest * maximumDimension).rounded(.down)))
        let height = max(1, Int((size.height / largest * maximumDimension).rounded(.down)))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let rectangle = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rectangle)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: rectangle, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        let output = NSMutableData()
        guard let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
            output.length <= VyronPDFAttachmentLimits.thumbnailMaximumBytes
        else { return nil }
        return output as Data
    }
}
