import Foundation
import XCTest
@testable import VyronCore

final class VyronOpenAICostEstimatorTests: XCTestCase {
    func testChargesEachInputCategoryOnceAndUsesExactDecimalDollars() throws {
        let usage = VyronOpenAITokenUsage(
            inputTokens: 1_000,
            outputTokens: 50,
            inputDetails: .init(cachedTokens: 200, cacheWrite30mTokens: 300, cacheWrite12hTokens: 100)
        )
        let actual = VyronOpenAICostEstimator.cost(for: observation(usage: usage))
        XCTAssertEqual(actual, try decimal("0.00257"))
    }

    func testLongContextThresholdChargesEntireRequestWithIndependentOutputFactor() throws {
        let short = observation(usage: tokens(input: 272_000, output: 1_000))
        let long = observation(usage: tokens(input: 272_001, output: 1_000))
        XCTAssertEqual(VyronOpenAICostEstimator.cost(for: short), try decimal("0.554"))
        XCTAssertEqual(VyronOpenAICostEstimator.cost(for: long), try decimal("1.103004"))
    }

    func testLongContextAlsoAdjustsCachedReadsAndWritesWithoutDoubleCharging() throws {
        let usage = VyronOpenAITokenUsage(
            inputTokens: 300_000, outputTokens: 1_000,
            inputDetails: .init(cachedTokens: 100_000, cacheWrite30mTokens: 100_000, cacheWrite12hTokens: 100_000)
        )
        XCTAssertEqual(VyronOpenAICostEstimator.cost(for: observation(usage: usage)), try decimal("1.535"))
    }

    func testVerifiedServiceTiersUseActualReturnedTierAndUnknownTiersStayUnpriced() throws {
        let usage = tokens(input: 1_000, output: 100)
        XCTAssertEqual(VyronOpenAICostEstimator.cost(for: observation(usage: usage)), try decimal("0.003"))
        for tier in ["fast", "priority"] {
            XCTAssertEqual(
                VyronOpenAICostEstimator.cost(for: observation(usage: usage, tier: tier)), try decimal("0.006")
            )
        }
        XCTAssertEqual(
            VyronOpenAICostEstimator.cost(for: observation(usage: usage, tier: "flex")), try decimal("0.0015")
        )
        XCTAssertEqual(
            VyronOpenAICostEstimator.cost(for: observation(usage: usage, tier: "ultrafast")), try decimal("0.018")
        )
        for tier in ["auto", "scale", "unknown", "", "DEFAULT"] {
            XCTAssertNil(VyronOpenAICostEstimator.cost(for: observation(usage: usage, tier: tier)))
        }
        XCTAssertNil(VyronOpenAICostEstimator.cost(for: observation(model: "gpt-4o", usage: usage, tier: "fast")))
        XCTAssertNil(VyronOpenAICostEstimator.cost(for: observation(model: "gpt-6.1-terra", usage: usage, tier: "ultrafast")))
    }

    func testLegacyModelsAndVerifiedSnapshotsKeepTheirOwnRates() throws {
        let usage = tokens(input: 1_000, output: 100)
        let expected: [String: String] = [
            "gpt-4o": "0.0035", "gpt-4o-2024-08-06": "0.0035", "gpt-4o-2024-11-20": "0.0035",
            "gpt-4o-mini-2024-07-18": "0.00021", "gpt-4.1": "0.0028",
            "gpt-4.1-mini-2025-04-14": "0.00056", "gpt-5-2025-08-07": "0.00225",
            "gpt-5-mini-2025-08-07": "0.00045", "gpt-5-nano": "0.00009",
            "gpt-5.1-2025-11-13": "0.00225", "gpt-5.2-2025-12-11": "0.00315",
            "gpt-5.3-codex": "0.00315"
        ]
        for (model, amount) in expected {
            XCTAssertEqual(
                VyronOpenAICostEstimator.cost(for: observation(model: model, usage: usage)),
                try decimal(amount), model
            )
        }
    }

    func testEveryCurrentFamilyHasIndependentVerifiedStandardRates() throws {
        let usage = tokens(input: 1_000, output: 100)
        let expected: [String: String] = [
            "gpt-6-astra": "0.015", "gpt-6-sol": "0.003", "gpt-6.1-sol": "0.003",
            "gpt-6.1-terra": "0.0015", "gpt-6-luna": "0.00015",
            "gpt-5.6-sol": "0.006", "gpt-5.6-cyber": "0.02"
        ]
        for (model, amount) in expected {
            XCTAssertEqual(
                VyronOpenAICostEstimator.cost(for: observation(model: model, usage: usage, tier: "default")),
                try decimal(amount), model
            )
        }
    }

    func testLegacyCacheReadsGetDiscountButUnsupportedWritesNeverBecomeFree() throws {
        let usage = VyronOpenAITokenUsage(
            inputTokens: 1_000, outputTokens: 200,
            inputDetails: .init(cachedTokens: 500, cacheWrite30mTokens: 0, cacheWrite12hTokens: 0)
        )
        XCTAssertEqual(
            VyronOpenAICostEstimator.cost(for: observation(model: "gpt-4o-mini", usage: usage)),
            try decimal("0.0002325")
        )
        let writes = VyronOpenAITokenUsage(
            inputTokens: 1_000, outputTokens: 100,
            inputDetails: .init(cachedTokens: 0, cacheWrite30mTokens: 1, cacheWrite12hTokens: 0)
        )
        XCTAssertNil(VyronOpenAICostEstimator.cost(for: observation(model: "gpt-4o-mini", usage: writes)))
    }

    func testUnknownAliasesAndModelVariantsNeverBorrowAnotherModelsRate() {
        for model in ["", "gpt-6.1-sol-2099-01-01", "gpt-5-turbo", "ft:gpt-4o:custom", "gpt-4o-2024-05-13"] {
            XCTAssertFalse(VyronOpenAICostEstimator.supports(model: model))
            XCTAssertNil(VyronOpenAICostEstimator.cost(for: observation(model: model, usage: tokens(input: 0, output: 0))))
        }
    }

    func testUnavailableUsageCannotBecomeZeroOrEstimatedFromVisibleText() {
        for reason in [VyronOpenAIUsageUnavailable.missingUsage, .invalidUsage, .interrupted, .unsupportedModality] {
            let record = VyronOpenAIUsageObservation(
                responseID: "resp_test", model: "gpt-6.1-sol", serviceTier: nil, result: .unavailable(reason)
            )
            XCTAssertNil(VyronOpenAICostEstimator.cost(for: record))
        }
    }

    func testInvalidAndOverflowingCategoryCountsAreRejectedWithoutTrapping() {
        let invalid: [VyronOpenAITokenUsage] = [
            tokens(input: -1, output: 1), tokens(input: 1, output: -1),
            .init(inputTokens: 10, outputTokens: 1, inputDetails: .init(
                cachedTokens: -1, cacheWrite30mTokens: 0, cacheWrite12hTokens: 0
            )),
            .init(inputTokens: 10, outputTokens: 1, inputDetails: .init(
                cachedTokens: 9, cacheWrite30mTokens: 1, cacheWrite12hTokens: 1
            )),
            .init(inputTokens: Int.max, outputTokens: 1, inputDetails: .init(
                cachedTokens: Int.max, cacheWrite30mTokens: Int.max, cacheWrite12hTokens: Int.max
            ))
        ]
        for usage in invalid {
            XCTAssertNil(VyronOpenAICostEstimator.cost(for: observation(usage: usage)))
        }
    }

    func testReportedZeroUsageIsZeroAndLargeValidCountsRemainFinite() throws {
        XCTAssertEqual(VyronOpenAICostEstimator.cost(for: observation(usage: tokens(input: 0, output: 0))), 0)
        let actual = try XCTUnwrap(VyronOpenAICostEstimator.cost(for: observation(usage: tokens(
            input: Int.max, output: Int.max
        ))))
        XCTAssertFalse(actual.isNaN)
        XCTAssertGreaterThan(actual, 0)
    }

    private func observation(
        model: String = "gpt-6.1-sol",
        usage: VyronOpenAITokenUsage,
        tier: String? = nil
    ) -> VyronOpenAIUsageObservation {
        VyronOpenAIUsageObservation(responseID: "resp_test", model: model, serviceTier: tier, result: .measured(usage))
    }

    private func tokens(input: Int, output: Int) -> VyronOpenAITokenUsage {
        VyronOpenAITokenUsage(
            inputTokens: input, outputTokens: output,
            inputDetails: .init(cachedTokens: 0, cacheWrite30mTokens: 0, cacheWrite12hTokens: 0)
        )
    }

    private func decimal(_ value: String) throws -> Decimal {
        try XCTUnwrap(Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")))
    }
}
