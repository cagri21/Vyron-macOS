import VyronLocalization
import VyronModelDomain

/// Classifies recovery failures without recording provider bodies, prompt text or credentials.
enum VyronDevelopmentInferenceDiagnostic {
    static func code(for error: any Error) -> String {
        if (error as? DevelopmentAgentError) == .contextBudget { return "context_budget" }
        guard let local = error as? LocalAIError else { return String(reflecting: type(of: error)) }
        switch local {
        case .invalidResponse(let detail):
            if detail == VyronModelDataText.ollamaChatNoAnswer { return "ollama_chat_no_answer" }
            if detail == VyronModelDataText.ollamaChatContextExceeded { return "ollama_chat_context_exceeded" }
            if detail == VyronModelDataText.malformedStreamingData { return "ollama_malformed_stream" }
            if detail == VyronModelDataText.responseLineTooLarge { return "ollama_stream_line_too_large" }
            if detail.contains("XML syntax error") { return "ollama_tool_parse_error" }
            return "ollama_invalid_response"
        case .httpError(let status, _): return "ollama_http_\(status)"
        case .requestTimedOut: return "ollama_request_timed_out"
        case .connectionFailed: return "ollama_connection_failed"
        case .incompleteStream: return "ollama_incomplete_stream"
        default: return "ollama_request_failed"
        }
    }
}
