import VyronLocalization
import VyronModelDomain

/// Qwen3 Coder's renderer retains only the first system message, so native guidance must share that message.
enum VyronOllamaDevelopmentSystemMessages {
    static func coalescing(_ messages: [DevelopmentMessage], model: String) throws -> [DevelopmentMessage] {
        guard developmentUsesFunctionXMLGrammar(model) else { return messages }
        let systems = messages.filter { $0.role == "system" }
        guard systems.allSatisfy({
            $0.toolCalls == nil && $0.toolName == nil && $0.toolCallID == nil
                && $0.images == nil && $0.imageObservation == nil && $0.continuation == nil
        }) else {
            // Merging structured system metadata would silently discard information or change its authority.
            throw LocalAIError.invalidResponse(VyronModelDataText.unsupportedMessageRole)
        }
        guard systems.count > 1 else { return messages }
        let system = DevelopmentMessage(role: "system", content: systems.map(\.content).joined(separator: "\n\n"))
        return [system] + messages.filter { $0.role != "system" }
    }
}
