import Foundation
import XCTest
@testable import VyronCore

enum VyronDevelopmentAgentWireFixture {
    static func metadata(_ request: URLRequest) throws -> Data? {
        guard request.url?.path == "/api/show" else { return nil }
        let body = try fields(request)
        let model = try XCTUnwrap(body["model"] as? String)
        let supported = ["qwen3-coder:30b", "qwen3:4b", "devstral-small-2:24b"]
        guard supported.contains(model) else {
            XCTFail("Unexpected model metadata request: \(model)")
            throw URLError(.unsupportedURL)
        }
        let capabilities = model == "qwen3:4b" ? ["completion", "tools", "thinking"] : ["completion", "tools"]
        return try JSONSerialization.data(withJSONObject: [
            "capabilities": capabilities,
            "model_info": ["fixture.context_length": 32_768]
        ])
    }

    static func chatFields(_ request: URLRequest) throws -> [String: Any] {
        XCTAssertEqual(request.url?.path, "/api/chat", "Only actual inference requests have messages and options")
        guard request.url?.path == "/api/chat" else { throw URLError(.unsupportedURL) }
        return try fields(request)
    }

    static func fields(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: body(request)) as? [String: Any])
    }

    static func messages(_ fields: [String: Any]) throws -> [DevelopmentMessage] {
        let value = try XCTUnwrap(fields["messages"], "An inference request must retain its message array")
        return try JSONDecoder().decode(
            [DevelopmentMessage].self, from: JSONSerialization.data(withJSONObject: value)
        )
    }

    static func hasRecordedResult(for tool: String, in messages: [DevelopmentMessage]) -> Bool {
        messages.contains {
            $0.toolName == tool || (
                VyronDevelopmentExchangeCompactor.isCompactedReference($0)
                    && $0.content.contains(tool + " recorded result:")
            )
        }
    }

    private static func body(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw URLError(.cannotDecodeRawData) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
