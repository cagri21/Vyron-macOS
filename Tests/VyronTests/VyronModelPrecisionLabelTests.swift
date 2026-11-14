import XCTest
@testable import Vyron

final class VyronModelPrecisionLabelTests: XCTestCase {
    func testKnownQuantizationsShowBitDepthAndPreserveFormat() {
        let examples = [("nvfp4", 4), ("MXFP4", 4), ("MXFP8", 8), ("Q8_0", 8), ("BF16", 16)]

        for (format, bits) in examples {
            let label = VyronModelPrecisionLabel.text(format)
            XCTAssertEqual(label, VyronAppText.settingsPrecisionBits(bits, format))
            XCTAssertTrue(label.hasSuffix("(\(format))"))
        }
    }

    func testUnknownQuantizationKeepsReportedFormat() {
        XCTAssertEqual(VyronModelPrecisionLabel.text("custom-format"), "custom-format")
    }
}
