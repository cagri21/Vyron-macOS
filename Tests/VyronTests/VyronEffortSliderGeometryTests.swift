import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronEffortSliderGeometryTests: XCTestCase {
    func testEveryLevelMapsBetweenThumbCentersAndFillStopsExactlyAtThumbCenter() {
        for position in 0...5 {
            let geometry = VyronEffortSliderGeometry(width: 240, position: Double(position))
            let expectedLeading = (240 - CGFloat(28)) * CGFloat(position) / 5
            XCTAssertEqual(geometry.thumbDiameter, 28)
            XCTAssertEqual(geometry.thumbLeading, expectedLeading, accuracy: 0.000_001)
            XCTAssertEqual(geometry.thumbCenter, expectedLeading + 14, accuracy: 0.000_001)
            XCTAssertEqual(geometry.fillWidth, geometry.thumbCenter, accuracy: 0.000_001)
            XCTAssertEqual(geometry.position(at: geometry.thumbCenter), Double(position), accuracy: 0.000_001)
            XCTAssertGreaterThanOrEqual(geometry.fillWidth, 0)
            XCTAssertLessThanOrEqual(geometry.fillWidth, 240)
        }
    }

    func testNarrowAndInvalidWidthsKeepThumbAndFillInsideAvailableGeometry() {
        let widths: [CGFloat] = [0, 12, 28, 240, -10, .nan, .infinity, -.infinity]
        for width in widths {
            let expectedWidth = width.isFinite ? max(0, width) : 0
            for position in [Double(-10), 0, 1, 2, 3, 4, 5, 10, .nan, .infinity] {
                let geometry = VyronEffortSliderGeometry(width: width, position: position)
                XCTAssertEqual(geometry.thumbDiameter, min(expectedWidth, 28))
                XCTAssertTrue(geometry.thumbLeading.isFinite)
                XCTAssertTrue(geometry.thumbCenter.isFinite)
                XCTAssertTrue(geometry.fillWidth.isFinite)
                XCTAssertGreaterThanOrEqual(geometry.thumbLeading, 0)
                XCTAssertLessThanOrEqual(geometry.thumbLeading + geometry.thumbDiameter, expectedWidth)
                XCTAssertEqual(geometry.fillWidth, geometry.thumbCenter, accuracy: 0.000_001)
                XCTAssertLessThanOrEqual(geometry.fillWidth, expectedWidth)
            }
        }
    }

    func testDragEndpointsClampAndNonfiniteInputPreservesCurrentSanitizedPosition() {
        let geometry = VyronEffortSliderGeometry(width: 240, position: 4)
        XCTAssertEqual(geometry.position(at: -1_000), 0)
        XCTAssertEqual(geometry.position(at: 1_000), 5)
        for x in [CGFloat.nan, .infinity, -.infinity] {
            XCTAssertEqual(geometry.position(at: x), 4)
        }
        let invalid = VyronEffortSliderGeometry(width: 240, position: .nan)
        XCTAssertEqual(invalid.position(at: .nan), 1)
        for width in [CGFloat.zero, 12, 28] {
            let collapsed = VyronEffortSliderGeometry(width: width, position: 3)
            XCTAssertEqual(collapsed.position(at: -1_000), 3)
            XCTAssertEqual(collapsed.position(at: 1_000), 3)
        }
    }
}
