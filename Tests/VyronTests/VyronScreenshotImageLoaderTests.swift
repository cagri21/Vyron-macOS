import Foundation
import ImageIO
import XCTest
import VyronCore
@testable import Vyron

final class VyronScreenshotImageLoaderTests: XCTestCase {
    func testImportNormalizesOrientationBoundsDimensionsAndRemovesLocationMetadata() async throws {
        let data = try VyronScreenshotTestImage.jpeg(width: 4_096, height: 1_024, orientation: 6)
        let image = try await VyronScreenshotImageLoader().load(data, name: "Device.jpg")

        XCTAssertEqual(image.name, "Device.jpg")
        XCTAssertEqual(image.mimeType, "image/png")
        XCTAssertTrue(image.data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(image.data as CFData, nil))
        let bitmap = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(bitmap.width, 512)
        XCTAssertEqual(bitmap.height, 2_048)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertLessThanOrEqual(image.data.count, VyronImageAttachment.maximumDataBytes)
    }

    func testInvalidDataIsRejectedInsteadOfAttachedAsAnImage() async throws {
        do {
            _ = try await VyronScreenshotImageLoader().load(Data("not an image".utf8), name: "bad.png")
            XCTFail("Invalid image bytes were accepted.")
        } catch {
            XCTAssertTrue(error is VyronScreenshotImportError)
        }
    }

    func testOversizedImportIsRejectedBeforeDecoding() async throws {
        let data = Data(repeating: 0, count: VyronScreenshotLimits.maximumImportBytes + 1)
        do {
            _ = try await VyronScreenshotImageLoader().load(data, name: "large.png")
            XCTFail("An oversized image was accepted.")
        } catch let error as VyronScreenshotImportError {
            guard case .tooLarge = error else { return XCTFail("Expected the image size error.") }
        }
    }

    func testCanceledImportRemainsCancellation() async throws {
        let data = try VyronScreenshotTestImage.jpeg()
        let loader = VyronScreenshotImageLoader()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await loader.load(data, name: "Canceled.jpg")
        }
        do {
            _ = try await task.value
            XCTFail("Canceled image import returned a result.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
