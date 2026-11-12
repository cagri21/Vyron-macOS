import Foundation
import XCTest
@testable import VyronCore

@MainActor
final class VyronConnectionBalanceAdapterTests: XCTestCase {
    func testDeepSeekReturnsExactSeparateCurrenciesAndProviderTotalsWithoutConversion() async throws {
        let body = """
            {"is_available":false,"balance_infos":[
            {"currency":"CNY","total_balance":"-0.00000000000000000001","granted_balance":"0","topped_up_balance":"0"},
            {"currency":"USD","total_balance":"12345678901234567890.123456789012345678",
             "granted_balance":"99","topped_up_balance":"100"}]}
            """
        await VyronConnectionBalanceTestURLProtocol.state.configure { _ in .init(body: body) }
        let result = try await VyronConnectionBalanceTestSupport.client().fetchBalance(
            for: VyronConnectionBalanceTestSupport.profile(), apiKey: VyronConnectionBalanceTestSupport.key
        )
        XCTAssertEqual(result.scope, .account)
        XCTAssertEqual(result.checkedAt, VyronConnectionBalanceTestSupport.checkedAt)
        XCTAssertEqual(result.amounts.map(\.currency), ["CNY", "USD"])
        XCTAssertEqual(result.amounts.map(\.amount), [
            try VyronConnectionBalanceTestSupport.decimal("-0.00000000000000000001"),
            try VyronConnectionBalanceTestSupport.decimal("12345678901234567890.123456789012345678")
        ])
        let requests = await VyronConnectionBalanceTestURLProtocol.state.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/user/balance")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + VyronConnectionBalanceTestSupport.key)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.timeoutInterval, 15)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testOpenRouterReportsExactUSDKeyAllowanceRatherThanAccountBalanceOrComputedUsage() async throws {
        let body = """
            {"data":{"limit_remaining":12345678901234567890.123456789012345678,"limit":1,"usage":999}}
            """
        await VyronConnectionBalanceTestURLProtocol.state.configure { _ in .init(body: body) }
        let result = try await VyronConnectionBalanceTestSupport.client().fetchBalance(
            for: VyronConnectionBalanceTestSupport.profile("https://openrouter.ai/api/v1"),
            apiKey: VyronConnectionBalanceTestSupport.key
        )
        XCTAssertEqual(result.scope, .keyAllowance)
        XCTAssertEqual(result.amounts, [VyronConnectionBalanceAmount(
            currency: "USD", amount: try VyronConnectionBalanceTestSupport.decimal(
                "12345678901234567890.123456789012345678"
            )
        )])
        let requests = await VyronConnectionBalanceTestURLProtocol.state.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://openrouter.ai/api/v1/key")
        XCTAssertFalse(requests.contains { $0.url?.path.hasSuffix("/credits") == true })
    }

    func testZeroAndNegativeRemainingAmountsAreNotClampedOrTreatedAsNoLimit() async throws {
        for amount in ["0", "-0.25", "1.25e-5"] {
            let body = #"{"data":{"limit_remaining":\#(amount)}}"#
            await VyronConnectionBalanceTestURLProtocol.state.configure { _ in .init(body: body) }
            let result = try await VyronConnectionBalanceTestSupport.client().fetchBalance(
                for: VyronConnectionBalanceTestSupport.profile("https://openrouter.ai/api/v1"),
                apiKey: VyronConnectionBalanceTestSupport.key
            )
            XCTAssertEqual(result.amounts.first?.amount, try VyronConnectionBalanceTestSupport.decimal(amount))
            XCTAssertEqual(result.scope, .keyAllowance)
        }
    }

    func testExplicitNullKeyAllowanceIsNoKeyLimitAndNeverAZeroBalance() async throws {
        await VyronConnectionBalanceTestURLProtocol.state.configure { _ in
            .init(body: #"{"data":{"limit_remaining":null,"limit":100,"usage":40}}"#)
        }
        do {
            _ = try await VyronConnectionBalanceTestSupport.client().fetchBalance(
                for: VyronConnectionBalanceTestSupport.profile("https://openrouter.ai/api/v1"),
                apiKey: VyronConnectionBalanceTestSupport.key
            )
            XCTFail("An unbounded key does not expose an account balance or a numeric remaining allowance.")
        } catch {
            XCTAssertEqual(error as? VyronConnectionBalanceError, .noKeyLimit)
        }
    }

    func testMissingMalformedOrOverPreciseProviderAmountsFailInsteadOfGuessing() async throws {
        let openRouterBodies = [
            #"{"data":{"limit":100,"usage":40}}"#, #"{"data":{"limit_remaining":"12.50"}}"#,
            #"{"data":{"limit_remaining":true}}"#, #"{"data":{"limit_remaining":1e999}}"#,
            #"{"data":{"limit_remaining":1.234567890123456789012345678901234567890}}"#,
            #"{"data":null}"#, #"{"balance":10}"#, "not JSON"
        ]
        for body in openRouterBodies {
            await VyronConnectionBalanceTestURLProtocol.state.configure { _ in .init(body: body) }
            do {
                _ = try await VyronConnectionBalanceTestSupport.client().fetchBalance(
                    for: VyronConnectionBalanceTestSupport.profile("https://openrouter.ai/api/v1"),
                    apiKey: VyronConnectionBalanceTestSupport.key
                )
                XCTFail("Malformed balance information must not become a displayed amount.")
            } catch {
                XCTAssertEqual(error as? VyronConnectionBalanceError, .invalidResponse)
            }
        }
        for total in ["", "NaN", "Infinity", "1.2suffix", "1,000.00", " 1.00", "1e-999"] {
            let body = try VyronConnectionBalanceTestSupport.deepSeek(total: total)
            await VyronConnectionBalanceTestURLProtocol.state.configure { _ in .init(body: body) }
            do {
                _ = try await VyronConnectionBalanceTestSupport.client().fetchBalance(
                    for: VyronConnectionBalanceTestSupport.profile(), apiKey: VyronConnectionBalanceTestSupport.key
                )
                XCTFail("Malformed monetary strings must not be coerced to a balance.")
            } catch {
                XCTAssertEqual(error as? VyronConnectionBalanceError, .invalidResponse)
            }
        }
    }

    func testDeepSeekRequiresItsActualBoundedCurrencyRecords() async throws {
        let bodies = [
            #"{"is_available":true,"balance_infos":[]}"#,
            #"{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"1"}]}"#,
            #"{"is_available":true,"balance_infos":[{"currency":"EUR","total_balance":"1","granted_balance":"0","topped_up_balance":"1"}]}"#,
            #"{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"1","granted_balance":"0","topped_up_balance":"1"},{"currency":"USD","total_balance":"2","granted_balance":"0","topped_up_balance":"2"}]}"#
        ]
        for body in bodies {
            await VyronConnectionBalanceTestURLProtocol.state.configure { _ in .init(body: body) }
            do {
                _ = try await VyronConnectionBalanceTestSupport.client().fetchBalance(
                    for: VyronConnectionBalanceTestSupport.profile(), apiKey: VyronConnectionBalanceTestSupport.key
                )
                XCTFail("Missing or ambiguous provider records must not be combined.")
            } catch {
                XCTAssertEqual(error as? VyronConnectionBalanceError, .invalidResponse)
            }
        }
    }
}
