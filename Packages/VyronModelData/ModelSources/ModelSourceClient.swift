import Foundation
import VyronModelDomain

/// Discovers real source variants and imports a selected single-file GGUF into local Ollama.
/// File transfer, hashing, and upload use files and bounded buffers rather than loading weights in memory.
public actor ModelSourceClient {
    typealias DownloadHandler =
        @Sendable (URLRequest, @escaping @Sendable (ModelPullProgress) -> Void) async throws -> (URL, URLResponse)
    let ollamaEndpoint: URL
    let sourceSession: URLSession
    let importSession: URLSession
    let downloadHandler: DownloadHandler?

    public init(ollamaEndpoint: URL = URL(string: "http://127.0.0.1:11434")!) {
        self.init(ollamaEndpoint: ollamaEndpoint, configuration: .ephemeral)
    }

    init(ollamaEndpoint: URL, configuration: URLSessionConfiguration, downloadHandler: DownloadHandler? = nil) {
        self.ollamaEndpoint = ollamaEndpoint
        self.downloadHandler = downloadHandler
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = VyronModelSourceLimits.requestTimeout
        configuration.timeoutIntervalForResource = VyronModelSourceLimits.resourceTimeout
        sourceSession = URLSession(
            configuration: configuration,
            delegate: ModelSourceRedirectDelegate(),
            delegateQueue: nil
        )
        configuration.connectionProxyDictionary = [:]
        importSession = URLSession(
            configuration: configuration,
            delegate: ModelImportRedirectDelegate(),
            delegateQueue: nil
        )
    }

    deinit {
        sourceSession.invalidateAndCancel()
        importSession.invalidateAndCancel()
    }

    public static func validateSourceURL(_ url: URL) throws -> URL {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let host = parts.host?.lowercased(), !host.isEmpty,
            parts.user == nil, parts.password == nil, parts.fragment == nil,
            parts.scheme?.lowercased() == VyronModelEndpointPolicy.secureScheme
                || (parts.scheme?.lowercased() == VyronModelEndpointPolicy.insecureScheme
                    && VyronModelEndpointPolicy.loopbackHosts.contains(host)),
            parts.port.map(VyronModelEndpointPolicy.validPorts.contains) ?? true
        else { throw ModelSourceError.invalidURL }
        return url
    }

    func metadata(
        _ request: URLRequest,
        using session: URLSession? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await (session ?? sourceSession).bytes(for: request)
        defer { bytes.task.cancel() }
        try Self.checkResponse(response)
        guard let http = response as? HTTPURLResponse else { throw ModelSourceError.invalidMetadata }
        guard response.expectedContentLength <= VyronModelSourceLimits.maximumMetadataBytes else {
            throw ModelSourceError.metadataTooLarge
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < VyronModelSourceLimits.maximumMetadataBytes else { throw ModelSourceError.metadataTooLarge }
            data.append(byte)
        }
        return (data, http)
    }

    static func checkResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw ModelSourceError.invalidMetadata }
        guard (200..<300).contains(http.statusCode) else { throw ModelSourceError.httpStatus(http.statusCode) }
    }
}
