import Foundation
import VyronLocalization
import VyronModelDomain

/// Classifies usable inference envelopes without retaining private thinking or failed response content.
enum VyronOllamaDevelopmentReplyIssue: Sendable {
    case emptyCompletion
    case unexpectedEmptyCompletion
    case outputLimitBeforeResponse
    case outputLimitBeforeAnswer

    init?(reply: DevelopmentStepResponse) {
        guard reply.done == true, let message = reply.message, message.role == "assistant",
            message.toolCalls?.isEmpty != false
        else { return nil }
        let hasContent = !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if reply.doneReason == "length" {
            self = hasContent ? .outputLimitBeforeAnswer : .outputLimitBeforeResponse
        } else if !hasContent {
            self =
                reply.doneReason == nil || reply.doneReason == "stop"
                ? .emptyCompletion : .unexpectedEmptyCompletion
        } else {
            return nil
        }
    }

    var errorDetail: String {
        switch self {
        case .emptyCompletion, .unexpectedEmptyCompletion:
            VyronModelDataText.ollamaNoAnswerOrTool
        case .outputLimitBeforeResponse:
            VyronModelDataText.ollamaOutputLimitBeforeResponse
        case .outputLimitBeforeAnswer:
            VyronModelDataText.ollamaOutputLimitBeforeAnswer
        }
    }

    var canRepair: Bool {
        switch self {
        case .emptyCompletion, .outputLimitBeforeResponse, .outputLimitBeforeAnswer: true
        case .unexpectedEmptyCompletion: false
        }
    }

    func repairMessages(_ messages: [DevelopmentMessage]) -> [DevelopmentMessage] {
        VyronDevelopmentRequestBudget.compactingCompletedExchanges(in: messages) + [DevelopmentMessage(
            role: "system",
            content: """
            The previous model response did not provide a complete usable answer or native tool call. No tool call from that response was executed. Continue the SAME original task using the same selected model and request limits. Preserve all original scope, user guidance, Plan-mode restrictions and command approval requirements. Completed tool exchanges and saved checkpoints are reference evidence; do not repeat recorded actions. Re-read current files before editing. Produce either a concise complete answer or valid native tool_calls using this model's runtime tool protocol. Printed commands or tool markup are not executable actions. Private thinking is not a final answer. If you cannot finish within the available budget, report the unfinished work honestly.
            """
        )]
    }
}
