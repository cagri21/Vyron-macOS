import Foundation
import VyronLocalization
import VyronModelDomain

struct VyronAnthropicTransport: Sendable {
    private static let apiVersion = "2026-10-21"
    private static let requestTimeout: TimeInterval = 180
    private static let tokenCountResponseBytes = 4_096
    private static let modelPageLimit = 20
    private static let modelsPath = "models"
    private static let messagesPath = "messages"
    private static let tokenCountPath = "messages/count_tokens"

    let endpoint: URL
    let apiKey: String?
    let session: URLSession

    func models() async throws -> [LocalModel] {
        var models: [LocalModel] = []
        var seenCursors: Set<String> = []
        var cursor: String?
        for _ in 0..<Self.modelPageLimit {
            let request = try modelListRequest(after: cursor)
            let data: Data
            do {
                data = try await responseData(request, limit: VyronAnthropicWire.maximumResponseBytes)
            } catch ModelProviderError.http(let status) where [404, 405, 501].contains(status) {
                throw ModelProviderError.modelListUnavailable
            }
            let page = try JSONDecoder().decode(VyronAnthropicModelPage.self, from: data)
            for model in page.data {
                try ModelEndpoint.validateModelID(model.id)
                models.append(LocalModel(name: model.id, size: 0))
            }
            guard page.hasMore else { return models }
            guard let lastID = page.lastID, !lastID.isEmpty, seenCursors.insert(lastID).inserted else {
                throw ModelProviderError.invalidResponse(VyronModelDataText.claudeInvalidCatalogCursor)
            }
            cursor = lastID
        }
        throw ModelProviderError.invalidResponse(VyronModelDataText.claudeTooManyCatalogPages)
    }

    func countInputTokens(_ body: Data) async throws -> Int {
        let data = try await responseData(
            request(path: Self.tokenCountPath, body: body),
            limit: Self.tokenCountResponseBytes
        )
        let response = try JSONDecoder().decode([String: Int].self, from: data)
        guard let count = response["input_tokens"], count > 0 else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.invalidInputTokenCount)
        }
        try Task.checkCancellation()
        return count
    }

    func completion(
        _ body: Data,
        stream: Bool,
        model: String,
        prefixDigest: Data? = nil
    ) async throws -> DevelopmentMessage {
        if stream {
            let parser = try await self.stream(body, model: model, prefixDigest: prefixDigest, onToken: { _ in })
            return try parser.developmentMessage()
        }
        let data = try await responseData(
            request(path: Self.messagesPath, body: body),
            limit: VyronAnthropicWire.maximumResponseBytes
        )
        return try VyronAnthropicWire.developmentMessage(data, model: model, prefixDigest: prefixDigest)
    }

    func stream(
        _ body: Data,
        model: String,
        prefixDigest: Data? = nil,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> VyronAnthropicStream {
        var request = request(path: Self.messagesPath, body: body)
        request.setValue(VyronModelHTTP.eventStream, forHTTPHeaderField: VyronModelHTTP.acceptHeader)
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        try validate(response)
        var parser = VyronAnthropicStream(model: model, prefixDigest: prefixDigest)
        for try await byte in bytes {
            try Task.checkCancellation()
            let delta = try parser.append(byte)
            if !delta.isEmpty { onToken(delta) }
            if parser.completed { break }
        }
        let delta = try parser.finish()
        if !delta.isEmpty { onToken(delta) }
        try Task.checkCancellation()
        return parser
    }

    private func modelListRequest(after cursor: String?) throws -> URLRequest {
        var result = request(path: Self.modelsPath)
        guard let cursor else { return result }
        guard let url = result.url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ModelProviderError.invalidEndpoint
        }
        parts.queryItems = [URLQueryItem(name: "after_id", value: cursor)]
        guard let paginatedURL = parts.url else { throw ModelProviderError.invalidEndpoint }
        result.url = paginatedURL
        return result
    }

    private func request(path: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: endpoint.appendingPathComponent(path), timeoutInterval: Self.requestTimeout)
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(VyronModelHTTP.json, forHTTPHeaderField: VyronModelHTTP.acceptHeader)
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "x-api-key") }
        if let body {
            request.httpMethod = VyronModelHTTP.post
            request.setValue(VyronModelHTTP.json, forHTTPHeaderField: VyronModelHTTP.contentTypeHeader)
            request.httpBody = body
        }
        return request
    }

    private func responseData(_ request: URLRequest, limit: Int) async throws -> Data {
        try Task.checkCancellation()
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        try validate(response)
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw ModelProviderError.invalidResponse(VyronModelDataText.responseTooLarge) }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.missingHTTPResponse)
        }
        guard (200..<300).contains(http.statusCode) else { throw ModelProviderError.http(http.statusCode) }
    }
}
