import Foundation

/// Per-instance transport behavior. It is never serialized into saved model settings.
struct VyronOpenAIResponsesTransport: Sendable {
    let configuration: URLSessionConfiguration
    let automaticReasoning: Bool

    init(configuration: URLSessionConfiguration, automaticReasoning: Bool = false) {
        self.configuration = configuration
        self.automaticReasoning = automaticReasoning
    }
}
