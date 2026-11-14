import Foundation

/// URLSession requires this callback object to cross threads; mutable fixture state is separately locked.
final class VyronOllamaDevelopmentRepairURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = VyronOllamaDevelopmentRepairState()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let url = request.url else { throw URLError(.badURL) }
            let data: Data
            let status: Int
            switch url.path {
            case "/api/tags":
                data = Data(#"{"models":[{"name":"qwen3-coder:30b","size":19000000000,"capabilities":["completion","tools","thinking"]}]}"#.utf8)
                status = 200
            case "/api/show":
                data = Data(#"{"capabilities":["completion","tools","thinking"],"thinking":{"values":[false,true]},"model_info":{"qwen3.context_length":32768}}"#.utf8)
                status = 200
            case "/api/chat":
                data = try Self.state.response(to: requestBody(), timeout: request.timeoutInterval)
                status = Self.state.responseStatus
            default:
                throw URLError(.unsupportedURL)
            }
            guard let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
            ) else { throw URLError(.badServerResponse) }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func requestBody() throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { throw URLError(.cannotDecodeContentData) }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            body.append(contentsOf: buffer.prefix(count))
        }
        return body
    }
}
