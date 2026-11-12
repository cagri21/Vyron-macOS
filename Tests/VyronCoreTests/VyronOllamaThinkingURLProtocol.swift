import Foundation

/// URLSession's callback boundary requires Sendable; this fixture has no shared mutable state.
final class VyronOllamaThinkingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let thinkingCapabilities = ["completion", "tools", "thinking"]
    private static let plainCapabilities = ["completion", "tools"]
    private static let models = [
        "plain:latest", "unknown:latest", "named:latest", "boolean:latest", "false-only:latest",
        "true-only:latest", "off-only:latest", "unknown-level:latest", "legacy:latest", "qwen3.8:27b", "metadata-failure:latest",
        "cancelled-metadata:latest", "step-empty:latest", "step-whitespace:latest", "step-length:latest",
        "step-truncated:latest", "step-call:latest", "stale-caps:latest"
    ]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let url = request.url else { throw URLError(.badURL) }
            let body = try requestBody()
            let model = body["model"] as? String ?? ""
            if model == "cancelled-metadata:latest" { throw URLError(.cancelled) }
            let status = model == "metadata-failure:latest" ? 500 : 200
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ) else { throw URLError(.badServerResponse) }
            let data = try responseBody(path: url.path, model: model, request: body)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private func responseBody(path: String, model: String, request: [String: Any]) throws -> Data {
        let body: [String: Any]
        switch path {
        case "/api/tags":
            body = ["models": Self.models.map { name -> [String: Any] in
                var value: [String: Any] = ["name": name, "size": 100]
                if name != "unknown:latest" && name != "qwen3.8:27b" {
                    value["capabilities"] = name == "plain:latest" || name == "stale-caps:latest"
                        ? Self.plainCapabilities : Self.thinkingCapabilities
                }
                return value
            }]
        case "/api/show":
            switch model {
            case "plain:latest", "unknown:latest":
                body = ["capabilities": Self.plainCapabilities]
            case "named:latest", "stale-caps:latest":
                body = ["capabilities": Self.thinkingCapabilities, "thinking": ["values": ["low", "high"]]]
            case "boolean:latest":
                body = ["capabilities": Self.thinkingCapabilities, "thinking": ["values": [false, true]]]
            case "false-only:latest":
                body = [
                    "capabilities": Self.thinkingCapabilities,
                    "thinking": ["values": [false, "low", "high"] as [Any]]
                ]
            case "true-only:latest":
                body = ["capabilities": Self.thinkingCapabilities, "thinking": ["values": [true]]]
            case "off-only:latest":
                body = ["capabilities": Self.thinkingCapabilities, "thinking": ["values": [false]]]
            case "unknown-level:latest":
                body = ["capabilities": Self.thinkingCapabilities, "thinking": ["values": ["minimal", "extreme"]]]
            case "step-empty:latest", "step-whitespace:latest", "step-length:latest", "step-truncated:latest",
                 "step-call:latest":
                body = ["capabilities": Self.thinkingCapabilities, "thinking": ["values": ["low", "high"]]]
            case "legacy:latest":
                body = ["capabilities": Self.thinkingCapabilities]
            case "qwen3.8:27b":
                body = [:]
            case "metadata-failure:latest":
                body = ["error": "Metadata unavailable"]
            default:
                throw URLError(.unsupportedURL)
            }
        case "/api/chat":
            if model.hasPrefix("step-") {
                let content = model == "step-whitespace:latest" ? " \n\t" : model == "step-truncated:latest" ? "Partial" : ""
                var message: [String: Any] = [
                    "role": "assistant", "content": content, "thinking": "NATIVE_REASONING_MARKER"
                ]
                if model == "step-call:latest" {
                    message["tool_calls"] = [["function": ["name": "list_files", "arguments": ["path": "."]]]]
                }
                let reason = model == "step-length:latest" || model == "step-truncated:latest" ? "length" : "stop"
                body = ["message": message, "done": true, "done_reason": reason]
                break
            }
            let content = (request["think"] as? String)
                ?? (request["think"] as? Bool).map { $0 ? "true" : "false" } ?? "omitted"
            body = ["message": ["role": "assistant", "content": content,
                                "thinking": "NATIVE_REASONING_MARKER final"], "done": true]
        default:
            throw URLError(.unsupportedURL)
        }
        var data = Data()
        if path == "/api/chat", request["stream"] as? Bool == true {
            data.append(Data("{\"message\":{\"role\":\"assistant\",\"thinking\":\"NATIVE_REASONING_MARKER\"},\"done\":false}\n".utf8))
        }
        data.append(try JSONSerialization.data(withJSONObject: body))
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
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotDecodeContentData)
        }
        return object
    }
}
