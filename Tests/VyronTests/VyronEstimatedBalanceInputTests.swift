import Foundation
import XCTest
@testable import Vyron

final class VyronEstimatedBalanceInputTests: XCTestCase {
    func testLocaleDecimalsAreExactAndDoNotAcceptAmbiguousGrouping() throws {
        let expected = try XCTUnwrap(Decimal(string: "1234.56000001"))
        XCTAssertEqual(VyronEstimatedBalanceInput.amount("1234.56000001", locale: Locale(identifier: "en_US")), expected)
        XCTAssertEqual(VyronEstimatedBalanceInput.amount("1234,56000001", locale: Locale(identifier: "tr_TR")), expected)
        XCTAssertEqual(VyronEstimatedBalanceInput.amount("1234,56000001", locale: Locale(identifier: "uk_UA")), expected)
        for text in ["1,234.56", "12,34", "USD 12.34", "$12.34"] {
            XCTAssertNil(VyronEstimatedBalanceInput.amount(text, locale: Locale(identifier: "en_US")), text)
        }
        for text in ["1.234,56", "12.34", "1 234,56", "1\u{00a0}234,56"] {
            XCTAssertNil(VyronEstimatedBalanceInput.amount(text, locale: Locale(identifier: "tr_TR")), text)
        }
    }

    func testInvalidInputCannotSilentlyBecomeZero() {
        for text in ["", " ", ".", "-1", "-0", "+1", "NaN", "Infinity", "1e2", "12abc", "1.2.3", "１２"] {
            XCTAssertNil(VyronEstimatedBalanceInput.amount(text, locale: Locale(identifier: "en_US")), text)
        }
        XCTAssertEqual(VyronEstimatedBalanceInput.amount("0", locale: Locale(identifier: "en_US")), 0)
        XCTAssertEqual(VyronEstimatedBalanceInput.amount(" 12.50\n", locale: Locale(identifier: "en_US")), Decimal(12.5))
        XCTAssertEqual(VyronEstimatedBalanceInput.amount(".25", locale: Locale(identifier: "en_US")), Decimal(0.25))
    }

    func testBoundsAndFractionLimitAreValidatedBeforeSaving() throws {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(VyronEstimatedBalanceInput.amount("1000000000", locale: locale), Decimal(1_000_000_000))
        XCTAssertEqual(VyronEstimatedBalanceInput.amount("0.00000001", locale: locale), Decimal(string: "0.00000001"))
        for text in ["1000000000.00000001", "1000000001", "0.000000001", String(repeating: "9", count: 200)] {
            XCTAssertNil(VyronEstimatedBalanceInput.amount(text, locale: locale), text)
        }
    }

}
