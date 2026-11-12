import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronConnectionBalancePresentationTests: XCTestCase {
    func testAmountsUseLocaleSpecificNumbersAndExplicitCurrencyWithoutDroppingPrecision() throws {
        let amount = VyronConnectionBalanceAmount(
            currency: "USD", amount: try XCTUnwrap(Decimal(string: "1234.56"))
        )
        let english = VyronConnectionBalancePresentation.amount(amount, locale: Locale(identifier: "en_US"))
        let turkish = VyronConnectionBalancePresentation.amount(amount, locale: Locale(identifier: "tr_TR"))
        let ukrainian = VyronConnectionBalancePresentation.amount(amount, locale: Locale(identifier: "uk_UA"))
        for text in [english, turkish, ukrainian] { XCTAssertTrue(text.contains("USD")) }
        XCTAssertTrue(english.contains("1,234.56"))
        XCTAssertTrue(turkish.contains("1.234,56"))
        XCTAssertTrue(ukrainian.filter { !$0.isWhitespace }.contains("1234,56"))
        XCTAssertNotEqual(english, turkish)
        let small = VyronConnectionBalanceAmount(
            currency: "USD", amount: try XCTUnwrap(Decimal(string: "0.00012345"))
        )
        XCTAssertTrue(VyronConnectionBalancePresentation.amount(
            small, locale: Locale(identifier: "en_US")
        ).contains("0.00012345"))
    }

    func testMultipleCurrenciesRemainSeparateAndKeyAllowanceNeverBecomesAccountBalance() {
        let amounts = [
            VyronConnectionBalanceAmount(currency: "USD", amount: 12),
            VyronConnectionBalanceAmount(currency: "EUR", amount: 8)
        ]
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let account = VyronConnectionBalanceSnapshot(amounts: amounts, scope: .account, checkedAt: date)
        let allowance = VyronConnectionBalanceSnapshot(amounts: amounts, scope: .keyAllowance, checkedAt: date)
        let locale = Locale(identifier: "en_US")
        let expected = amounts.map { VyronConnectionBalancePresentation.amount($0, locale: locale) }
            .joined(separator: " · ")
        XCTAssertEqual(VyronConnectionBalancePresentation.value(account, locale: locale), expected)
        XCTAssertEqual(
            VyronConnectionBalancePresentation.value(allowance, locale: locale),
            VyronBalanceText.keyAllowanceCompact(expected)
        )
        XCTAssertTrue(expected.contains("USD"))
        XCTAssertTrue(expected.contains("EUR"))
        XCTAssertEqual(expected.components(separatedBy: " · ").count, 2)
        XCTAssertFalse(expected.contains("20.00"))
        XCTAssertEqual(VyronConnectionBalancePresentation.scope(.account), VyronBalanceText.accountBalance)
        XCTAssertEqual(VyronConnectionBalancePresentation.scope(.keyAllowance), VyronBalanceText.keyAllowance)
        XCTAssertNotEqual(VyronBalanceText.accountBalance, VyronBalanceText.keyAllowance)
    }

    func testMissingAndNoKeyLimitStatesNeverFabricateNumericZeroOrReuseAnOldAllowance() {
        let locale = Locale(identifier: "en_US")
        let missing = VyronConnectionBalanceState(support: .openRouter, snapshot: nil, phase: .idle, lastAttempt: nil)
        XCTAssertEqual(
            VyronConnectionBalancePresentation.badge(missing, locale: locale, isStale: false),
            VyronBalanceText.unavailable
        )
        let prior = VyronConnectionBalanceSnapshot(
            amounts: [VyronConnectionBalanceAmount(currency: "USD", amount: 12)],
            scope: .keyAllowance, checkedAt: Date()
        )
        let noLimit = VyronConnectionBalanceState(
            support: .openRouter, snapshot: prior, phase: .failed(.noKeyLimit), lastAttempt: nil
        )
        let text = VyronConnectionBalancePresentation.badge(noLimit, locale: locale, isStale: true)
        XCTAssertEqual(text, VyronBalanceText.noKeyLimit)
        XCTAssertFalse(text.contains("12.00"))
        XCTAssertFalse(text.contains("0.00"))
        XCTAssertEqual(VyronConnectionBalancePresentation.explanation(noLimit), VyronBalanceText.noKeyLimitDescription)
        let empty = VyronConnectionBalanceSnapshot(amounts: [], scope: .account, checkedAt: Date())
        XCTAssertEqual(VyronConnectionBalancePresentation.value(empty, locale: locale), VyronBalanceText.unavailable)
    }

    func testRetainedStaleValueIsLabeledLastKnownAndErrorExplanationRemainsSeparate() {
        let locale = Locale(identifier: "en_US")
        let snapshot = VyronConnectionBalanceSnapshot(
            amounts: [VyronConnectionBalanceAmount(currency: "USD", amount: 7)], scope: .account,
            checkedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let state = VyronConnectionBalanceState(
            support: .deepSeek, snapshot: snapshot, phase: .failed(.connectionFailed), lastAttempt: Date()
        )
        let number = VyronConnectionBalancePresentation.value(snapshot, locale: locale)
        XCTAssertEqual(
            VyronConnectionBalancePresentation.badge(state, locale: locale, isStale: true),
            VyronBalanceText.lastKnown(number)
        )
        XCTAssertNotEqual(VyronBalanceText.lastKnown(number), number)
        XCTAssertEqual(VyronConnectionBalancePresentation.explanation(state), VyronBalanceText.connectionFailed)
        var locked = state
        locked.phase = .credentialUnavailable
        XCTAssertEqual(
            VyronConnectionBalancePresentation.badge(locked, locale: locale, isStale: true),
            VyronBalanceText.lastKnown(number)
        )
        XCTAssertEqual(VyronConnectionBalancePresentation.explanation(locked), VyronBalanceText.credentialUnavailable)
    }
}
