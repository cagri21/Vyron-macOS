import Foundation
import VyronModelData

public final class VyronLocalAuthHTTPTransport: VyronLocalAuthTransport {
    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.connectionProxyDictionary = [:]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = VyronLocalAuthLimits.timeout
        configuration.timeoutIntervalForResource = VyronLocalAuthLimits.timeout
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: ProviderRejectRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func data(for request: URLRequest) async throws -> VyronLocalAuthHTTPResponse {
        do {
            try validate(request)
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { throw VyronLocalAuthError.invalidResponse }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < VyronLocalAuthLimits.responseBytes else { throw VyronLocalAuthError.invalidResponse }
                data.append(byte)
            }
            try Task.checkCancellation()
            return VyronLocalAuthHTTPResponse(statusCode: http.statusCode, data: data)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                throw CancellationError()
            }
            if let known = error as? VyronLocalAuthError { throw known }
            throw VyronLocalAuthError.unavailable
        }
    }

    private func validate(_ request: URLRequest) throws {
        guard let url = request.url, url.scheme == "http", url.host == "127.0.0.1", url.port == 8327,
            url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
            request.value(forHTTPHeaderField: "Origin") == nil,
            request.value(forHTTPHeaderField: "Referer") == nil,
            request.httpBody?.count ?? 0 <= VyronLocalAuthLimits.responseBytes else {
            throw VyronLocalAuthError.invalidConfiguration
        }
        let credentialPrefix = "/v1/credentials/"
        let credentialPath = url.path.hasPrefix(credentialPrefix)
            && UUID(uuidString: String(url.path.dropFirst(credentialPrefix.count))) != nil
        guard (url.path == "/v1/session" && request.httpMethod == "GET")
            || (credentialPath && ["GET", "PUT", "DELETE"].contains(request.httpMethod ?? "")) else {
            throw VyronLocalAuthError.invalidConfiguration
        }
    }
}
