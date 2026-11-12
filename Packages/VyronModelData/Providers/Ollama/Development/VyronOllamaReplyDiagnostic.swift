import VyronModelDomain

package struct VyronOllamaReplyDiagnostic: Sendable {
    let attempt: Int
    let issue: VyronOllamaDevelopmentReplyIssue
    let request: VyronOllamaRequestMetrics
    let response: VyronOllamaResponseMetrics

    package var summary: String {
        "issue=\(issue), adapter_attempt=\(attempt), done_reason=\(response.finishReason), "
            + "context_tokens=\(request.contextTokens), output_limit=\(request.outputTokens), "
            + "message_bytes=\(request.messageBytes), schema_bytes=\(request.schemaBytes), "
            + "generated_tokens=\(response.generatedTokens.map(String.init) ?? "unknown"), "
            + "prompt_tokens=\(response.promptTokens.map(String.init) ?? "unknown")"
    }
}
