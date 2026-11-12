import CoreGraphics
import Foundation
import XCTest
import VyronAutomation

final class VyronMacControlPreviewTests: XCTestCase {
    func testNativeCoordinatesProjectIntoSelectedWindowOnAnotherDisplay() throws {
        let preview = preview(frame: CGRect(x: -1_440, y: 120, width: 1_000, height: 800))
        let target = CGRect(x: -1_190, y: 320, width: 100, height: 80)
        let unit = try XCTUnwrap(preview.unitRect(for: target))
        XCTAssertEqual(unit.minX, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(unit.minY, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(unit.width, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(unit.height, 0.1, accuracy: 0.000_001)
    }

    func testTargetHighlightClipsToCapturedWindow() throws {
        let preview = preview(frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        let unit = try XCTUnwrap(preview.unitRect(for: CGRect(x: 50, y: 50, width: 100, height: 100)))
        XCTAssertEqual(unit.minX, 0)
        XCTAssertEqual(unit.minY, 0)
        XCTAssertEqual(unit.width, 0.125, accuracy: 0.000_001)
        XCTAssertEqual(unit.height, 1 / 6, accuracy: 0.000_001)
    }

    func testTargetsOutsideWindowAndInvalidGeometryDoNotCreateHighlights() {
        let preview = preview(frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        XCTAssertNil(preview.unitRect(for: CGRect(x: 600, y: 100, width: 20, height: 20)))
        XCTAssertNil(preview.unitRect(for: .zero))
        XCTAssertNil(preview.unitRect(for: .null))
        XCTAssertNil(preview.unitRect(for: .infinite))
        XCTAssertNil(preview.unitRect(for: CGRect(x: CGFloat.nan, y: 100, width: 20, height: 20)))
        XCTAssertNil(self.preview(frame: .zero).unitRect(for: CGRect(x: 0, y: 0, width: 20, height: 20)))
    }

    private func preview(frame: CGRect) -> VyronMacControlPreview {
        VyronMacControlPreview(
            applicationID: "com.apple.TextEdit",
            capturedAt: Date(timeIntervalSince1970: 1),
            screenFrame: frame,
            imageData: Data()
        )
    }
}
