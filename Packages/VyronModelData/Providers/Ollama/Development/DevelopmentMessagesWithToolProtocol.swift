import Foundation
import VyronModelDomain

func developmentMessagesWithToolProtocol(_ messages: [DevelopmentMessage], model: String) -> [DevelopmentMessage] {
    guard developmentUsesFunctionXMLGrammar(model) else { return messages }
    let reminder =
        "\nNative tool formatting: follow the exact function-call format in the Tools section, including the required outer <tool_call> and </tool_call> delimiters around each <function=...> block. A bare function block is ordinary text and will NOT execute. Do not omit the outer delimiters. Only Ollama API tool_calls are executable."
    var adapted = messages
    if let index = adapted.firstIndex(where: { $0.role == "system" }) {
        let message = adapted[index]
        guard !message.content.contains(reminder) else { return messages }
        adapted[index] = DevelopmentMessage(
            role: message.role,
            content: message.content + reminder,
            toolCalls: message.toolCalls,
            toolName: message.toolName,
            toolCallID: message.toolCallID
        )
    } else {
        adapted.insert(DevelopmentMessage(role: "system", content: reminder), at: 0)
    }
    return adapted
}
