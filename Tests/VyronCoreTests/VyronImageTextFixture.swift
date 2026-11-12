import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VyronCore
import XCTest

enum VyronImageTextFixture {
    static func image(text: String) throws -> VyronImageAttachment {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 1_000,
            height: 200,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1_000, height: 200))
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 56, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ])
        context.textPosition = CGPoint(x: 40, y: 80)
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        let pixels = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, pixels, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return VyronImageAttachment(name: "OCR fixture.png", mimeType: "image/png", data: data as Data)
    }
}
