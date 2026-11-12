import Foundation
import XCTest
@testable import VyronCore

@MainActor
final class VyronConnectionBalanceTransportTests: XCTestCase {
    func testHTTPAndTransportFailuresDoNotExposeBodiesKeysOrErrorDescriptionsOrRetry() async throws {
        let privateMarker = "offline-balance-key PRIVATE_PROVIDER_BODY"
        for status in [401, 403, 429, 500, 302] {
            await VyronConnectionBalanceTestURLProtocol.state.configure { _ in
                .init(body: privateMarker, statusCode: status, headers: ["Location": "https://other.example/collect"])
            }
            do {
                _ = try await VyronConnectionBalanceTestSupport.client().fetchBalance(
                    for: VyronConnectionBalanceTestSupport.profile(), apiKey: VyronConnectionBalanceTestSupport.key
                )
                XCTFail("The status must be handled without parsing a response body or retrying.")
            } catch {
                let expected: VyronConnectionBalanceError
                if status == 401 || status == 403 { expected = .authenticationFailed }
                else if status == 429 { expected = .rateLimited }
                else { expected = .temporarilyUnavailable }
                XCTAssertEqual(error as? VyronConnectionBalanceError, expected)
                XCTAssertFalse(error.localizedDescription.contains("offline-balance-key"))
                XCTAssertFalse(error.localizedDescription.contains("PRIVATE_PROVIDER_BODY"))
            }
            let requests = await VyronConnectionBalanceTestURLProtocol.state.requests
            XCTAssertEqual(requests.count, 1)
            XCTAssertTrue(requests.allSatisfy { $0.url?.host == "api.deepseek.com" })
        }
        await VyronConnectionBalanceTestURLProtocol.state.configure { _ in
            throw NSError(domain: "PrivateTransport", code: 1, userInfo: [NSLocalizedDescriptionKey: privateMarker])
        }
        do {
            _ = try await VyronConnectionBalanceTestSupport.client().fetchBalance(
                for: VyronConnectionBalanceTestSupport.profile(), apiKey: VyronConnectionBalanceTestSupport.key
            )
            XCTFail("Transport failures must become a sanitized error.")
        } catch {
            XCTAssertEqual(error as? VyronConnectionBalanceError, .connectionFailed)
            XCTAssertFalse(error.localizedDescription.contains(privateMarker))
        }
    }

    func testStreamedResponseCannotExceed64KiBEvenWithoutContentLength() async throws {
        let body = String(repeating: " ", count: 65_537)
        await VyronConnectionBalanceTestURLProtocol.state.configure { _ in .init(body: body) }
        do {
            _ = try await VyronConnectionBalanceTestSupport.client().fetchBalance(
                for: VyronConnectionBalanceTestSupport.profile(), apiKey: VyronConnectionBalanceTestSupport.key
            )
            XCTFail("An oversized body must not be consumed or decoded.")
        } catch {
            XCTAssertEqual(error as? VyronConnectionBalanceError, .invalidResponse)
        }
        let requests = await VyronConnectionBalanceTestURLProtocol.state.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testCancellationBeforeRequestAndDuringResponseRemainsDistinctAndStopsTransport() async throws {
        await VyronConnectionBalanceTestURLProtocol.state.configure()
        let client = VyronConnectionBalanceTestSupport.client()
        let beforeStart = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.fetchBalance(
                for: VyronConnectionBalanceTestSupport.profile(), apiKey: VyronConnectionBalanceTestSupport.key
            )
        }
        do {
            _ = try await beforeStart.value
            XCTFail("Cancellation must stop before transport.")
        } catch is CancellationError {} catch { XCTFail("Cancellation must retain its type.") }
        let initial = await VyronConnectionBalanceTestURLProtocol.state.requests
        XCTAssertTrue(initial.isEmpty)

        let body = try VyronConnectionBalanceTestSupport.deepSeek()
        await VyronConnectionBalanceTestURLProtocol.state.configure { _ in .init(body: body, holdOpen: true) }
        let pending = Task {
            try await client.fetchBalance(
                for: VyronConnectionBalanceTestSupport.profile(), apiKey: VyronConnectionBalanceTestSupport.key
            )
        }
        try await VyronConnectionBalanceTestSupport.waitUntil {
            await VyronConnectionBalanceTestURLProtocol.state.requests.count == 1
        }
        pending.cancel()
        do {
            _ = try await pending.value
            XCTFail("Cancellation must stop the response.")
        } catch is CancellationError {} catch { XCTFail("Cancellation must retain its type.") }
        try await VyronConnectionBalanceTestSupport.waitUntil {
            await VyronConnectionBalanceTestURLProtocol.state.stopCount > 0
        }
        let requests = await VyronConnectionBalanceTestURLProtocol.state.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testRedirectDelegateNeverForwardsEvenAnAuthorizedRequestToAnotherHost() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronConnectionBalanceTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let source = try XCTUnwrap(URL(string: "https://api.deepseek.com/user/balance"))
        let destination = try XCTUnwrap(URL(string: "https://other.example/collect"))
        let task = session.dataTask(with: source) // Never resumed; this is a delegate-policy check only.
        let response = try XCTUnwrap(HTTPURLResponse(url: source, statusCode: 302, httpVersion: nil, headerFields: nil))
        var redirected = URLRequest(url: destination)
        redirected.setValue("Bearer " + VyronConnectionBalanceTestSupport.key, forHTTPHeaderField: "Authorization")
        let rejected = await withCheckedContinuation { continuation in
            ProviderRejectRedirects().urlSession(
                session, task: task, willPerformHTTPRedirection: response, newRequest: redirected
            ) { request in
                continuation.resume(returning: request == nil)
            }
        }
        XCTAssertTrue(rejected)
    }

    func testRateLimitPreservesNumericAndHTTPDateRetryAdviceWithoutRetryingOrExposingRawData() async throws {
        let advice: [String: TimeInterval] = [
            "0": 0, "120": 120, "Fri, 15 Jan 2027 08:03:00 GMT": 180
        ]
        for (header, seconds) in advice {
            await VyronConnectionBalanceTestURLProtocol.state.configure { _ in
                .init(body: "PRIVATE_PROVIDER_BODY", statusCode: 429, headers: ["Retry-After": header])
            }
            do {
                _ = try await VyronConnectionBalanceTestSupport.client().fetchBalance(
                    for: VyronConnectionBalanceTestSupport.profile(), apiKey: VyronConnectionBalanceTestSupport.key
                )
                XCTFail("Rate limiting must return sanitized advice rather than retrying.")
            } catch let failure as VyronConnectionBalanceRetryFailure {
                XCTAssertEqual(failure.error, .rateLimited)
                XCTAssertEqual(
                    failure.retryAfter, VyronConnectionBalanceTestSupport.checkedAt.addingTimeInterval(seconds)
                )
                XCTAssertEqual(failure.errorDescription, VyronConnectionBalanceError.rateLimited.errorDescription)
                XCTAssertFalse(failure.localizedDescription.contains("PRIVATE_PROVIDER_BODY"))
                XCTAssertFalse(failure.localizedDescription.contains("offline-balance-key"))
            } catch {
                XCTFail("Valid retry advice must retain its typed deadline.")
            }
            let requests = await VyronConnectionBalanceTestURLProtocol.state.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testMalformedRetryAdviceKeepsExistingPayloadFreeRateLimitError() async throws {
        for header in ["", "-1", "1.5", "NaN", "Infinity", "tomorrow", "Fri, 99 Jan 2027 08:03:00 GMT",
            String(repeating: "9", count: 350)] {
            await VyronConnectionBalanceTestURLProtocol.state.configure { _ in
                .init(body: "PRIVATE_PROVIDER_BODY", statusCode: 429, headers: ["Retry-After": header])
            }
            do {
                _ = try await VyronConnectionBalanceTestSupport.client().fetchBalance(
                    for: VyronConnectionBalanceTestSupport.profile(), apiKey: VyronConnectionBalanceTestSupport.key
                )
                XCTFail("Malformed retry advice must not become a deadline or a retry.")
            } catch {
                XCTAssertEqual(error as? VyronConnectionBalanceError, .rateLimited)
                XCTAssertFalse(error is VyronConnectionBalanceRetryFailure)
            }
            let requests = await VyronConnectionBalanceTestURLProtocol.state.requests
            XCTAssertEqual(requests.count, 1)
        }
    }
}
