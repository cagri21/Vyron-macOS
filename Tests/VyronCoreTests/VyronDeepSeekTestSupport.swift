import Foundation
@testable import VyronCore
@testable import VyronModelData

enum VyronDeepSeekTestSupport {
    static let model = VyronDeepSeekRoute.defaultModel

    static func profile(settings: ModelSettings = ModelSettings()) -> ModelConnectionProfile {
        ModelConnectionProfile(
            name: "Offline DeepSeek test", kind: .openAICompatible,
            endpoint: VyronDeepSeekRoute.endpoint, selectedModel: model, settings: settings
        )
    }

    static func client(_ profile: ModelConnectionProfile) throws -> OpenAICompatibleClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
        return try OpenAICompatibleClient(
            connection: profile, apiKey: "offline-deepseek-key", configuration: configuration
        )
    }

    static func models(_ model: String = model) throws -> VyronResponsesTestResponse {
        VyronResponsesTestResponse(body: try VyronResponsesTestSupport.json([
            "data": [["id": model, "capabilities": ["tools"]]]
        ]))
    }

    static func completion(
        content: String,
        reasoning: String = "private-final-reasoning",
        calls: [[String: Any]] = []
    ) throws -> VyronResponsesTestResponse {
        var message: [String: Any] = [
            "role": "assistant", "content": content, "reasoning_content": reasoning
        ]
        if !calls.isEmpty { message["tool_calls"] = calls }
        return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.json([
            "choices": [["finish_reason": calls.isEmpty ? "stop" : "tool_calls", "message": message]]
        ]))
    }

    static func call(id: String = "call-deepseek", name: String = "list_files") -> [String: Any] {
        ["id": id, "type": "function", "function": ["name": name, "arguments": "{}"]]
    }

    static func stream() -> String {
        "data: {\"choices\":[{\"index\":0,\"delta\":{\"reasoning_content\":\"private-stream-reasoning\"}}]}\n\n"
            + "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Visible answer\"},\"finish_reason\":\"stop\"}]}\n\n"
            + "data: [DONE]\n\n"
    }
}
