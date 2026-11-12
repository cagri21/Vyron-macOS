import Foundation
import VyronLocalization
import VyronModelDomain

extension OllamaClient {
    static func decodeLine<T: Decodable>(_ line: String) throws -> T {
        guard line.utf8.count <= VyronOllamaTransportLimits.maximumStreamLineBytes else {
            throw LocalAIError.invalidResponse(VyronModelDataText.responseLineTooLarge)
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(line.utf8))
        } catch {
            throw LocalAIError.invalidResponse(VyronModelDataText.malformedStreamingData)
        }
    }

    func makeRequest<Body: Encodable>(path: String, body: Body) throws -> URLRequest {
        let endpoint = try connectionEndpoint()
        var request = URLRequest(url: endpoint.appendingPathComponent("api").appendingPathComponent(path))
        request.httpMethod = VyronModelHTTP.post
        request.setValue(VyronModelHTTP.json, forHTTPHeaderField: VyronModelHTTP.contentTypeHeader)
        if let apiKey {
            request.setValue(VyronModelHTTP.bearer(apiKey), forHTTPHeaderField: VyronModelHTTP.authorizationHeader)
        }
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = VyronModelProviderSessionPolicy.resourceTimeout
        return request
    }

    /// Retries inference data only, never an action. Some local runners reject the format field.
    func structuredChatData<Body: Encodable>(for body: Body, maximumResponseBytes: Int) async throws -> Data {
        var request = try makeRequest(path: "chat", body: body)
        request.timeoutInterval = VyronOllamaTransportLimits.structuredInferenceTimeout
        for attempt in 0..<2 {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else {
                throw LocalAIError.invalidResponse(VyronModelDataText.missingHTTPResponse)
            }
            guard data.count <= maximumResponseBytes else {
                throw LocalAIError.invalidResponse(VyronModelDataText.structuredResponseTooLarge)
            }
            if (200..<300).contains(http.statusCode) { return data }
            let detail = Self.errorDetail(data)
            guard attempt == 0, http.statusCode == 501, detail == "structured output is unavailable",
                let original = request.httpBody,
                var object = try JSONSerialization.jsonObject(with: original) as? [String: Any],
                let schema = object.removeValue(forKey: "format"),
                var messages = object["messages"] as? [[String: String]],
                let systemIndex = messages.firstIndex(where: { $0["role"] == "system" }),
                let options = object["options"] as? [String: Any],
                let context = options["num_ctx"] as? Int,
                let output = options["num_predict"] as? Int
            else {
                throw httpError(http.statusCode, data: data)
            }
            let schemaJSON = String(
                decoding: try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys]),
                as: UTF8.self
            )
            messages[systemIndex]["content", default: ""] += """


            Return exactly ONE JSON object matching the JSON schema below. Return JSON only: no Markdown fences, commentary, tool markup, or additional fields. This is proposal/classification data only; no action has executed. Preserve the original goal, supplied evidence, and all original permission and target restrictions. Use null for unused nullable fields.
            JSON schema: \(schemaJSON)
            """
            let messageBytes = try JSONSerialization.data(withJSONObject: messages).count
            guard messageBytes + output + 2_048 <= context else {
                throw LocalAIError.invalidResponse(
                    VyronModelDataText.ollamaStructuredFallbackTooLarge
                )
            }
            object["messages"] = messages
            request.httpBody = try JSONSerialization.data(withJSONObject: object)
        }
        throw LocalAIError.invalidResponse(VyronModelDataText.ollamaStructuredResponseUnavailable)
    }

    func stream(_ request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        do {
            return try await session.bytes(for: request)
        } catch {
            throw Self.normalized(error)
        }
    }

    func validate(response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        guard let http = response as? HTTPURLResponse else {
            throw LocalAIError.invalidResponse(VyronModelDataText.missingHTTPResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count >= VyronOllamaTransportLimits.maximumErrorBodyBytes { break }
            }
            throw httpError(http.statusCode, data: body)
        }
    }

    private static func errorDetail(_ data: Data) -> String {
        return (try? JSONDecoder().decode(ServerError.self, from: data).error)
            .map { String($0.prefix(500)) } ?? ""
    }

    func httpError(_ status: Int, data: Data) -> Error {
        configuredConnection
            ? ModelProviderError.http(status) : LocalAIError.httpError(status, Self.errorDetail(data))
    }

    func serverError(_ detail: String) -> Error {
        configuredConnection
            ? ModelProviderError.invalidResponse(VyronModelDataText.serverInferenceError)
            : LocalAIError.invalidResponse(detail)
    }

    static func normalized(_ error: Error) -> Error {
        if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
            return CancellationError()
        }
        if error is LocalAIError { return error }
        if error is URLError { return LocalAIError.connectionFailed }
        return error
    }
}
