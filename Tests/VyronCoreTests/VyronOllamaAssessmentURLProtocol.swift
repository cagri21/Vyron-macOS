import Foundation

/// URLSession's callback boundary requires Sendable; this fixture has no shared mutable state.
final class VyronOllamaAssessmentURLProtocol: URLProtocol, @unchecked Sendable {
    private static let models = [
        "qwen3:4b", "boolean:latest", "mixed:latest", "off-only:latest", "named:latest", "plain:latest",
        "metadata-failure:latest", "cancelled-metadata:latest"
    ]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let url = request.url else { throw URLError(.badURL) }
            let input = try requestBody()
            let model = input["model"] as? String ?? ""
            if url.path == "/api/show", model == "cancelled-metadata:latest" { throw URLError(.cancelled) }
            let status = model == "metadata-failure:latest" ? 500 : 200
            let output = try responseBody(path: url.path, model: model, input: input)
            guard let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
            ) else { throw URLError(.badServerResponse) }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: output)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func responseBody(path: String, model: String, input: [String: Any]) throws -> Data {
        let output: [String: Any]
        switch path {
        case "/api/tags":
            output = ["models": Self.models.map { name in
                ["name": name, "size": 100, "capabilities": ["completion", "tools", "thinking"]] as [String: Any]
            }]
        case "/api/show":
            let values: [Any]
            switch model {
            case "qwen3:4b": values = [true]
            case "boolean:latest": values = [false, true]
            case "mixed:latest": values = [false, "low", "high"]
            case "off-only:latest": values = [false]
            case "named:latest": values = ["low", "high"]
            case "plain:latest": values = []
            case "metadata-failure:latest": return Data(#"{"error":"Metadata unavailable"}"#.utf8)
            default: throw URLError(.unsupportedURL)
            }
            output = [
                "capabilities": model == "plain:latest" ? ["completion", "tools"] : ["completion", "tools", "thinking"],
                "thinking": ["values": values], "model_info": ["qwen3.context_length": 32_768]
            ]
        case "/api/chat":
            // Echo the real serialized request through final content, keeping the native reasoning channel separate.
            let requestJSON = String(decoding: try JSONSerialization.data(withJSONObject: input), as: UTF8.self)
            output = [
                "message": ["role": "assistant", "content": requestJSON, "thinking": "PRIVATE_REASONING_MARKER"],
                "done": true
            ]
        default:
            throw URLError(.unsupportedURL)
        }
        var data = try JSONSerialization.data(withJSONObject: output)
        if path == "/api/chat" { data.append(10) }
        return data
    }

    private func requestBody() throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
                if count == 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        guard !data.isEmpty else { return [:] }
        guard let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotDecodeContentData)
        }
        return fields
    }
}
