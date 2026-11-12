import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronEstimatedBalancePresentationTests: XCTestCase {
    func testMissingEstimateAsksForBalanceInsteadOfShowingZero() {
        let text = VyronConnectionBalancePresentation.estimatedBadge(nil, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(text, VyronEstimatedBalanceText.setBalance)
        XCTAssertFalse(text.contains("0.00"))
    }

    func testEveryRemainingAmountRetainsEstimateLabelAndExplicitUSDCurrency() throws {
        let locale = Locale(identifier: "en_US")
        for amount in ["12.3456789", "0", "-0.003"] {
            let value = try XCTUnwrap(Decimal(string: amount))
            for incomplete in [false, true] {
                let estimate = VyronEstimatedBalanceState(
                    remainingUSD: value, updatedAt: Date(), hasUntrackedUsage: incomplete
                )
                let formatted = VyronConnectionBalancePresentation.estimatedAmount(value, locale: locale)
                let badge = VyronConnectionBalancePresentation.estimatedBadge(estimate, locale: locale)
                XCTAssertEqual(badge, VyronEstimatedBalanceText.remaining(formatted))
                XCTAssertTrue(badge.contains("USD"))
                XCTAssertNotEqual(badge, formatted)
                if value < 0 { XCTAssertTrue(badge.contains("-")) }
            }
        }
    }

    func testLocalizedResourceMembershipIncludesEstimateAndRecoveryLabels() {
        let keys = [
            "estimatedBalanceTitle", "estimatedBalanceRemaining", "estimatedBalanceSetBalance",
            "estimatedBalanceCurrentBalance", "estimatedBalanceAmountPlaceholder", "estimatedBalanceSaveBalance",
            "estimatedBalanceUpdateBalance", "estimatedBalanceSaved", "estimatedBalanceInvalidAmount",
            "estimatedBalanceExplanation", "estimatedBalanceUntrackedUsage", "estimatedBalanceStorageError",
            "estimatedBalanceCheckEstimate"
        ]
        for language in [VyronLanguage.english, .turkish, .ukrainian] {
            let bundle = VyronResourceBundle.localized(for: language)
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertNotEqual(value, key, "\(language.rawValue): \(key)")
                XCTAssertFalse(value.isEmpty)
            }
            let format = bundle.localizedString(forKey: "estimatedBalanceRemaining", value: nil, table: nil)
            XCTAssertEqual(format.components(separatedBy: "%@").count, 2)
        }
    }
}
