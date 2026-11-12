import Foundation
@testable import VyronCore

actor VyronWorkBudgetTransportState {
    private(set) var requests: [URLRequest] = []

    func reset() { requests = [] }

    func response(for request: URLRequest) throws -> Data {
        requests.append(request)
        if request.url?.path == "/v1/models" {
            return Data(#"{"data":[{"id":"gpt-6.1-sol","capabilities":["tools"]}]}"#.utf8)
        }
        if request.url?.path == "/v1/responses/input_tokens" {
            return Data(#"{"object":"response.input_tokens","input_tokens":9000}"#.utf8)
        }
        guard request.url?.path == "/v1/responses" else { throw URLError(.unsupportedURL) }
        let body = try Self.body(request)
        if (body["tool_choice"] as? [String: String])?["name"] == "vyron_check_tools" {
            let input = try JSONSerialization.data(withJSONObject: body["input"] ?? [])
            let prompt = String(decoding: input, as: UTF8.self)
            guard let range = prompt.range(of: "nonce ") else { throw URLError(.cannotDecodeRawData) }
            let nonce = String(prompt[range.upperBound...].prefix(36))
            guard UUID(uuidString: nonce) != nil else { throw URLError(.cannotDecodeRawData) }
            return try JSONSerialization.data(withJSONObject: [
                "status": "completed", "output": [[
                    "type": "function_call", "id": "fc_probe", "status": "completed",
                    "call_id": "probe-call", "name": "vyron_check_tools", "arguments": "{\"nonce\":\"\(nonce)\"}"
                ]]
            ])
        }
        return Data("""
        {"status":"completed","output":[{"type":"message","role":"assistant","status":"completed",
        "content":[{"type":"output_text","text":"Inspection complete."}]}]}
        """.utf8)
    }

    nonisolated static func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                if count == 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotDecodeRawData)
        }
        return body
    }
}
