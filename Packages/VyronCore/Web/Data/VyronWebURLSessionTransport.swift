import Foundation
import VyronModelData

struct VyronWebURLSessionTransport: VyronWebTransport {
    private let session: URLSession
    private let acceptedMediaTypes: [String]

    init(
        acceptedMediaTypes: [String] = VyronWebLimits.textMediaTypes,
        requestTimeout: TimeInterval = VyronWebLimits.requestTimeout,
        resourceTimeout: TimeInterval = VyronWebLimits.resourceTimeout
    ) {
        self.acceptedMediaTypes = acceptedMediaTypes
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        session = URLSession(configuration: configuration, delegate: ProviderRejectRedirects(), delegateQueue: nil)
    }

    func fetch(_ url: URL) async throws -> VyronWebResponse {
        let target = try await VyronWebURLPolicy.validatePublicHTTPS(url)
        var request = URLRequest(url: target)
        request.setValue(acceptedMediaTypes.joined(separator: ","), forHTTPHeaderField: "Accept")
        request.setValue("Vyron/1.0 (web research)", forHTTPHeaderField: "User-Agent")
        do {
            try Task.checkCancellation()
            let (bytes, rawResponse) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let response = rawResponse as? HTTPURLResponse,
                (200..<300).contains(response.statusCode), response.url == target
            else { throw VyronWebError.unavailable }
            let mediaType = response.mimeType?.lowercased() ?? ""
            guard acceptedMediaTypes.contains(mediaType) else {
                throw VyronWebError.unsupportedContent
            }
            guard response.expectedContentLength <= VyronWebLimits.responseBytes else {
                throw VyronWebError.responseTooLarge
            }
            var data = Data()
            for try await byte in bytes {
                if data.count % 4_096 == 0 { try Task.checkCancellation() }
                guard data.count < VyronWebLimits.responseBytes else { throw VyronWebError.responseTooLarge }
                data.append(byte)
            }
            try Task.checkCancellation()
            return VyronWebResponse(url: target, mediaType: mediaType, body: data)
        } catch {
            if error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            if let error = error as? VyronWebError { throw error }
            throw VyronWebError.unavailable
        }
    }
}
