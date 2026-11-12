import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

enum VyronOllamaOCRTestSupport {
    static let model = "qwen3-coder:30b"
    static let recognizedText = "Build failed: Missing required API_ENDPOINT configuration."

    static func image() throws -> VyronImageAttachment {
        let data = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aNl8AAAAASUVORK5CYII="
        ))
        return VyronImageAttachment(name: "Build output.png", mimeType: "image/png", data: data)
    }

    static func client(recognizer: any VyronImageTextRecognizing) throws -> OllamaClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronImageURLProtocol.self]
        let profile = ModelConnectionProfile(
            name: "OCR test", kind: .ollama, endpoint: "https://models.example.test",
            selectedModel: model, settings: ModelSettings(contextTokens: 32_768, maxOutputTokens: 512)
        )
        return try OllamaClient(
            connection: profile, configuration: configuration, imageTextRecognizer: recognizer
        )
    }

    static func metadata(for request: URLRequest, vision: Bool = false) -> (Int, String)? {
        let capabilities = vision ? #"["completion","tools","vision"]"# : #"["completion","tools"]"#
        switch request.url?.path {
        case "/api/tags":
            return (200, "{\"models\":[{\"name\":\"\(model)\",\"size\":100,\"capabilities\":\(capabilities)}]}")
        case "/api/show":
            return (200, "{\"capabilities\":\(capabilities),\"model_info\":{\"qwen3.context_length\":32768}}")
        default:
            return nil
        }
    }

    static func messages(in request: URLRequest) throws -> [[String: Any]] {
        try XCTUnwrap(try VyronResponsesTestSupport.body(request)["messages"] as? [[String: Any]])
    }

    static func assertNoPixels(_ messages: [[String: Any]]) {
        XCTAssertTrue(messages.allSatisfy { $0["images"] == nil })
        XCTAssertFalse(messages.contains { ($0["content"] as? String)?.contains("data:image/") == true })
    }

    static let reply = #"{"message":{"role":"assistant","content":"The screenshot text identifies a missing configuration value."},"done":true}"# + "\n"
}
