import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
import VyronCore

enum VyronScreenshotTestImage {
    static func jpeg(width: Int = 32, height: Int = 16, orientation: Int = 1) throws -> Data {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ))
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 41.0],
            kCGImageDestinationLossyCompressionQuality: 0.9
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            XCTFail("Could not encode the test image.")
            throw CocoaError(.fileWriteUnknown)
        }
        return output as Data
    }

    static func attachment(name: String = "Screenshot.jpg") throws -> VyronImageAttachment {
        VyronImageAttachment(name: name, mimeType: "image/jpeg", data: try jpeg())
    }
}
