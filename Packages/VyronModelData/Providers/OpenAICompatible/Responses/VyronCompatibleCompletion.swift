import Foundation
import VyronLocalization
import VyronModelDomain

struct VyronCompatibleCompletion: Decodable {
    let choices: [VyronCompatibleCompletionChoice]

    func developmentMessage() throws -> DevelopmentMessage {
        guard let first = choices.first, first.message.role == "assistant",
            ["stop", "tool_calls"].contains(first.finishReason ?? "")
        else { throw ModelProviderError.invalidResponse(VyronModelDataText.serverIncompleteAssistantResponse) }
        let calls = try first.message.toolCalls?.map { try $0.nativeCall() }
        guard (calls?.count ?? 0) <= 4, Set((calls ?? []).compactMap(\.id)).count == (calls?.count ?? 0) else {
            throw DevelopmentAgentError.invalidTool(VyronModelDataText.invalidOrDuplicateToolCallIDs)
        }
        if first.finishReason == "tool_calls", calls?.isEmpty != false {
            throw ModelProviderError.invalidResponse(VyronModelDataText.emptyToolResponse)
        }
        if (calls ?? []).isEmpty,
            (first.message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ModelProviderError.invalidResponse(VyronModelDataText.serverNoAnswerOrTool)
        }
        return DevelopmentMessage(role: "assistant", content: first.message.content ?? "", toolCalls: calls)
    }
}
