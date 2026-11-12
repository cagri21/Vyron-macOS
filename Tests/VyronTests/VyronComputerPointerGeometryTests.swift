import CoreGraphics
import XCTest
@testable import Vyron

final class VyronComputerPointerGeometryTests: XCTestCase {
    private let primary = CGRect(x: 0, y: 0, width: 1_000, height: 800)

    func testDesktopPointerChoosesDisplayWithMostVisibleTargetArea() throws {
        let secondary = CGRect(x: -900, y: 800, width: 900, height: 700)
        let target = CGRect(x: -260, y: -300, width: 460, height: 500)
        let frame = try XCTUnwrap(VyronComputerPointerGeometry.desktopFrame(
            for: target, primaryHeight: primary.height, screens: [primary, secondary]
        ))

        let size = VyronComputerPreviewStyle.pointerSize
        XCTAssertEqual(frame, CGRect(x: -130 - size / 2, y: 950 - size / 2, width: size, height: size))
        XCTAssertTrue(secondary.contains(frame))
    }

    func testDesktopPointerFitsWhenOnlyAnEdgeOfTargetIsVisible() throws {
        let target = CGRect(x: 998, y: 300, width: 100, height: 80)
        let frame = try XCTUnwrap(VyronComputerPointerGeometry.desktopFrame(
            for: target, primaryHeight: primary.height, screens: [primary]
        ))

        XCTAssertEqual(frame.midY, 460)
        XCTAssertEqual(frame.maxX, primary.maxX)
        XCTAssertTrue(primary.contains(frame))
    }

    func testDesktopPointerSkipsOffscreenTargetsAndGapsBetweenDisplays() {
        let secondary = CGRect(x: 1_200, y: 800, width: 600, height: 500)
        for target in [
            CGRect(x: 1_050, y: 100, width: 50, height: 50),
            CGRect(x: 2_000, y: 100, width: 50, height: 50)
        ] {
            XCTAssertNil(VyronComputerPointerGeometry.desktopFrame(
                for: target, primaryHeight: primary.height, screens: [primary, secondary]
            ))
        }
    }

    func testDesktopPointerSkipsInvalidBounds() {
        let invalidTargets: [CGRect] = [.null, .zero, .infinite]
        for target in invalidTargets {
            XCTAssertNil(VyronComputerPointerGeometry.desktopFrame(
                for: target, primaryHeight: primary.height, screens: [primary]
            ))
        }

        let valid = CGRect(x: 40, y: 50, width: 100, height: 100)
        XCTAssertNil(VyronComputerPointerGeometry.desktopFrame(
            for: valid, primaryHeight: .infinity, screens: [primary]
        ))
        XCTAssertNil(VyronComputerPointerGeometry.desktopFrame(
            for: valid, primaryHeight: primary.height, screens: []
        ))
    }

    func testPreviewPointerUsesTargetCenterAndRespectsImageOffset() {
        let image = CGRect(x: 80, y: 40, width: 600, height: 400)
        let target = CGRect(x: 0.125, y: 0.25, width: 0.25, height: 0.5)

        XCTAssertEqual(VyronComputerPointerGeometry.previewPoint(for: target, in: image), CGPoint(x: 230, y: 240))
    }

    func testPreviewPointerClampsToImageEdgesAndCentersInTinyPreview() {
        let image = CGRect(x: 80, y: 40, width: 600, height: 400)
        let target = CGRect(x: 0, y: 0.999, width: 0.001, height: 0.001)
        let halfSize = VyronComputerPreviewStyle.pointerSize / 2
        XCTAssertEqual(
            VyronComputerPointerGeometry.previewPoint(for: target, in: image),
            CGPoint(x: image.minX + halfSize, y: image.maxY - halfSize)
        )

        let smallImage = CGRect(x: 13, y: 41, width: 4, height: 6)
        XCTAssertEqual(
            VyronComputerPointerGeometry.previewPoint(for: target, in: smallImage),
            CGPoint(x: smallImage.midX, y: smallImage.midY)
        )
    }
}
