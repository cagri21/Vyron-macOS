import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

enum VyronConnectionBalanceTestSupport {
    static let key = "offline-balance-key"
    static let checkedAt = Date(timeIntervalSince1970: 1_800_000_000)

    static func client() -> VyronConnectionBalanceClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronConnectionBalanceTestURLProtocol.self]
        configuration.httpAdditionalHeaders = ["Cookie": "must-not-be-forwarded"]
        return VyronConnectionBalanceClient(configuration: configuration, now: { checkedAt })
    }

    static func profile(_ endpoint: String = "https://api.deepseek.com/v1") -> ModelConnectionProfile {
        ModelConnectionProfile(name: "Offline balance fixture", kind: .openAICompatible, endpoint: endpoint)
    }

    static func deepSeek(total: String = "1.25", currency: String = "USD") throws -> String {
        let body: [String: Any] = [
            "is_available": true,
            "balance_infos": [[
                "currency": currency, "total_balance": total, "granted_balance": "0.00", "topped_up_balance": total
            ]]
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
    }

    static func decimal(_ value: String) throws -> Decimal {
        try XCTUnwrap(Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")))
    }

    @MainActor
    static func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The offline balance request did not reach its expected state.")
        throw CancellationError()
    }
}
