import Foundation
import VyronModelDomain

public actor VyronConnectionBalanceClient: VyronConnectionBalanceProviding {
    private let session: URLSession
    private let now: @Sendable () -> Date

    public init() {
        self.init(configuration: .ephemeral)
    }

    init(configuration: URLSessionConfiguration, now: @escaping @Sendable () -> Date = { Date() }) {
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = VyronConnectionBalanceLimits.requestTimeout
        configuration.timeoutIntervalForResource = VyronConnectionBalanceLimits.resourceTimeout
        session = URLSession(configuration: configuration, delegate: ProviderRejectRedirects(), delegateQueue: nil)
        self.now = now
    }

    deinit { session.invalidateAndCancel() }

    public func fetchBalance(
        for profile: ModelConnectionProfile,
        apiKey: String
    ) async throws -> VyronConnectionBalanceSnapshot {
        try Task.checkCancellation()
        let support = VyronConnectionBalancePolicy.support(for: profile)
        guard support.canFetch else { throw VyronConnectionBalanceError.unsupported }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, apiKey.utf8.count <= VyronConnectionBalanceLimits.maximumKeyBytes,
            !apiKey.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
            key.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) })
        else { throw VyronConnectionBalanceError.missingKey }
        let endpoint =
            support == .deepSeek
            ? "https://api.deepseek.com/user/balance" : "https://openrouter.ai/api/v1/key"
        guard let url = URL(string: endpoint) else { throw VyronConnectionBalanceError.unsupported }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = VyronModelHTTP.get
        request.timeoutInterval = VyronConnectionBalanceLimits.requestTimeout
        request.setValue(VyronModelHTTP.bearer(key), forHTTPHeaderField: VyronModelHTTP.authorizationHeader)
        request.setValue(VyronModelHTTP.json, forHTTPHeaderField: VyronModelHTTP.acceptHeader)
        do {
            let data = try await responseData(for: request)
            try Task.checkCancellation()
            let result = try snapshot(data, support: support)
            try Task.checkCancellation()
            return result
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            if let retryFailure = error as? VyronConnectionBalanceRetryFailure { throw retryFailure }
            if let balanceError = error as? VyronConnectionBalanceError { throw balanceError }
            throw VyronConnectionBalanceError.connectionFailed
        }
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.url == request.url else {
            throw VyronConnectionBalanceError.invalidResponse
        }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw VyronConnectionBalanceError.authenticationFailed
        case 429:
            if let deadline = VyronConnectionBalanceRetryAdvice.deadline(
                from: http.value(forHTTPHeaderField: "Retry-After"),
                now: now()
            ) {
                throw VyronConnectionBalanceRetryFailure(error: .rateLimited, retryAfter: deadline)
            }
            throw VyronConnectionBalanceError.rateLimited
        default: throw VyronConnectionBalanceError.temporarilyUnavailable
        }
        guard response.expectedContentLength <= Int64(VyronConnectionBalanceLimits.responseBytes) else {
            throw VyronConnectionBalanceError.invalidResponse
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < VyronConnectionBalanceLimits.responseBytes else {
                throw VyronConnectionBalanceError.invalidResponse
            }
            data.append(byte)
        }
        return data
    }

    private func snapshot(
        _ data: Data,
        support: VyronConnectionBalanceSupport
    ) throws -> VyronConnectionBalanceSnapshot {
        do {
            try VyronConnectionBalanceJSONNumbers.validate(data)
            let amounts: [VyronConnectionBalanceAmount]
            let scope: VyronConnectionBalanceScope
            if support == .deepSeek {
                let response = try JSONDecoder().decode(VyronDeepSeekBalanceResponse.self, from: data)
                guard !response.balance_infos.isEmpty, response.balance_infos.count <= 2,
                    Set(response.balance_infos.map(\.currency)).count == response.balance_infos.count
                else { throw VyronConnectionBalanceError.invalidResponse }
                amounts = try response.balance_infos.map { value in
                    guard ["CNY", "USD"].contains(value.currency) else {
                        throw VyronConnectionBalanceError.invalidResponse
                    }
                    _ = try VyronConnectionBalanceDecimal.parse(value.granted_balance)
                    _ = try VyronConnectionBalanceDecimal.parse(value.topped_up_balance)
                    return VyronConnectionBalanceAmount(
                        currency: value.currency,
                        amount: try VyronConnectionBalanceDecimal.parse(value.total_balance)
                    )
                }
                scope = .account
            } else {
                let response = try JSONDecoder().decode(VyronOpenRouterKeyBalanceResponse.self, from: data)
                guard let remaining = response.data.limit_remaining else {
                    throw VyronConnectionBalanceError.noKeyLimit
                }
                amounts = [VyronConnectionBalanceAmount(currency: "USD", amount: remaining)]
                scope = .keyAllowance
            }
            return VyronConnectionBalanceSnapshot(amounts: amounts, scope: scope, checkedAt: now())
        } catch let error as VyronConnectionBalanceError {
            throw error
        } catch {
            throw VyronConnectionBalanceError.invalidResponse
        }
    }
}
