import Foundation
@testable import VyronCore
@testable import VyronModelData

enum VyronOllamaDevelopmentRepairFixture {
    static let model = "qwen3-coder:30b"

    static func client(settings: ModelSettings = ModelSettings()) throws -> OllamaClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronOllamaDevelopmentRepairURLProtocol.self]
        let profile = ModelConnectionProfile(
            name: "Offline development reply fixture", kind: .ollama,
            endpoint: "http://localhost:11434", selectedModel: model, settings: settings
        )
        return try OllamaClient(connection: profile, configuration: configuration)
    }

    static func reply(
        _ message: DevelopmentMessage,
        thinking: String? = nil,
        done: Bool? = true,
        reason: String? = nil
    ) throws -> Data {
        var wireMessage = try JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any]
        wireMessage?["thinking"] = thinking
        var reply: [String: Any] = ["message": wireMessage ?? [:]]
        reply["done"] = done
        reply["done_reason"] = reason
        return try JSONSerialization.data(withJSONObject: reply)
    }

    static func fields(_ data: Data) throws -> [String: DevelopmentJSONValue] {
        try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: data)
    }

    static func messages(in data: Data) throws -> [DevelopmentMessage] {
        guard let messages = try fields(data)["messages"] else { throw URLError(.cannotDecodeContentData) }
        return try JSONDecoder().decode([DevelopmentMessage].self, from: JSONEncoder().encode(messages))
    }
}
