import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

enum VyronResponsesTestSupport {
    static let model = "gpt-6.1-sol"

    static func profile(settings: ModelSettings = ModelSettings()) -> ModelConnectionProfile {
        ModelConnectionProfile(
            name: "Offline Responses test",
            kind: .openAICompatible,
            endpoint: "https://api.openai.com/v1",
            selectedModel: model,
            settings: settings
        )
    }

    static func client(settings: ModelSettings = ModelSettings()) throws -> VyronOpenAIResponsesClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
        return try VyronOpenAIResponsesClient(
            connection: profile(settings: settings), apiKey: "offline-test-key", configuration: configuration
        )
    }

    static func body(_ request: URLRequest) throws -> [String: Any] {
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
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func json(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
    }

    static func textOutput(_ text: String) -> [String: Any] {
        [
            "type": "message", "id": "msg_test", "role": "assistant", "status": "completed",
            "content": [["type": "output_text", "text": text, "annotations": []]]
        ]
    }

    static func completion(_ output: [[String: Any]], status: String = "completed") throws -> String {
        try json(["id": "resp_test", "status": status, "output": output])
    }

    static func toolOutput(_ id: String, name: String = "list_files", arguments: String = "{}") -> [String: Any] {
        [
            "type": "function_call", "id": "fc_" + id, "status": "completed",
            "call_id": id, "name": name, "arguments": arguments
        ]
    }

    static func reasoning(_ id: String = "rs_test") -> [String: Any] {
        [
            "type": "reasoning", "id": id, "summary": [], "content": [], "status": NSNull(),
            "encrypted_content": "opaque-" + id
        ]
    }

    static func modelList() -> VyronResponsesTestResponse {
        VyronResponsesTestResponse(body: #"{"data":[{"id":"gpt-6.1-sol","capabilities":["tools","vision"]}]}"#)
    }

    static func stream(_ text: String) throws -> String {
        "event: response.output_text.delta\n"
            + "data: " + (try json(["type": "response.output_text.delta", "delta": text])) + "\n\n"
            + "event: response.completed\n"
            + "data: " + (try json([
                "type": "response.completed",
                "response": ["status": "completed", "output": [textOutput(text)]]
            ])) + "\n\n"
    }
}
