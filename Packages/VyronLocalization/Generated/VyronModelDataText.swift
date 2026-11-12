// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

package enum VyronModelDataText {
    package static var activeConnectionMissing: String {
        VyronSharedResources.current.string("modelDataActiveConnectionMissing", fallback: "The saved active model connection is missing.")
    }

    package static func activeConnectionMissing(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataActiveConnectionMissing", fallback: "The saved active model connection is missing.", language: language)
    }
    package static var answerTooLarge: String {
        VyronSharedResources.current.string("modelDataAnswerTooLarge", fallback: "The answer is too large.")
    }

    package static func answerTooLarge(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataAnswerTooLarge", fallback: "The answer is too large.", language: language)
    }
    package static var apiKeyTooLong: String {
        VyronSharedResources.current.string("modelDataApiKeyTooLong", fallback: "The API key contains invalid characters or is too long.")
    }

    package static func apiKeyTooLong(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataApiKeyTooLong", fallback: "The API key contains invalid characters or is too long.", language: language)
    }
    package static var apiKeyUnsupportedCharacters: String {
        VyronSharedResources.current.string("modelDataApiKeyUnsupportedCharacters", fallback: "The API key contains unsupported characters.")
    }

    package static func apiKeyUnsupportedCharacters(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataApiKeyUnsupportedCharacters", fallback: "The API key contains unsupported characters.", language: language)
    }
    package static var claudeContinuationTooLarge: String {
        VyronSharedResources.current.string("modelDataClaudeContinuationTooLarge", fallback: "The Claude continuation is too large.")
    }

    package static func claudeContinuationTooLarge(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeContinuationTooLarge", fallback: "The Claude continuation is too large.", language: language)
    }
    package static var claudeDeclinedRequest: String {
        VyronSharedResources.current.string("modelDataClaudeDeclinedRequest", fallback: "Claude declined this request.")
    }

    package static func claudeDeclinedRequest(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeDeclinedRequest", fallback: "Claude declined this request.", language: language)
    }
    package static var claudeIncompleteResponse: String {
        VyronSharedResources.current.string("modelDataClaudeIncompleteResponse", fallback: "Claude did not return a complete response.")
    }

    package static func claudeIncompleteResponse(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeIncompleteResponse", fallback: "Claude did not return a complete response.", language: language)
    }
    package static var claudeInvalidCatalogCursor: String {
        VyronSharedResources.current.string("modelDataClaudeInvalidCatalogCursor", fallback: "Invalid Claude model list cursor.")
    }

    package static func claudeInvalidCatalogCursor(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeInvalidCatalogCursor", fallback: "Invalid Claude model list cursor.", language: language)
    }
    package static var claudeInvalidStreamContent: String {
        VyronSharedResources.current.string("modelDataClaudeInvalidStreamContent", fallback: "Claude returned an invalid streaming content update.")
    }

    package static func claudeInvalidStreamContent(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeInvalidStreamContent", fallback: "Claude returned an invalid streaming content update.", language: language)
    }
    package static var claudeInvalidStreamEvent: String {
        VyronSharedResources.current.string("modelDataClaudeInvalidStreamEvent", fallback: "Claude returned an invalid or incomplete streaming event.")
    }

    package static func claudeInvalidStreamEvent(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeInvalidStreamEvent", fallback: "Claude returned an invalid or incomplete streaming event.", language: language)
    }
    package static var claudeInvalidToolArguments: String {
        VyronSharedResources.current.string("modelDataClaudeInvalidToolArguments", fallback: "Claude returned malformed native tool arguments.")
    }

    package static func claudeInvalidToolArguments(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeInvalidToolArguments", fallback: "Claude returned malformed native tool arguments.", language: language)
    }
    package static var claudeInvalidToolCall: String {
        VyronSharedResources.current.string("modelDataClaudeInvalidToolCall", fallback: "Claude returned an invalid native tool call.")
    }

    package static func claudeInvalidToolCall(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeInvalidToolCall", fallback: "Claude returned an invalid native tool call.", language: language)
    }
    package static var claudeInvalidToolExchange: String {
        VyronSharedResources.current.string("modelDataClaudeInvalidToolExchange", fallback: "The conversation contains an invalid or incomplete Claude tool exchange.")
    }

    package static func claudeInvalidToolExchange(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeInvalidToolExchange", fallback: "The conversation contains an invalid or incomplete Claude tool exchange.", language: language)
    }
    package static var claudeInvalidToolIDs: String {
        VyronSharedResources.current.string("modelDataClaudeInvalidToolIDs", fallback: "Invalid or duplicate Claude tool call IDs.")
    }

    package static func claudeInvalidToolIDs(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeInvalidToolIDs", fallback: "Invalid or duplicate Claude tool call IDs.", language: language)
    }
    package static var claudeManagedControls: String {
        VyronSharedResources.current.string("modelDataClaudeManagedControls", fallback: "Claude uses model-managed sampling and thinking controls.")
    }

    package static func claudeManagedControls(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeManagedControls", fallback: "Claude uses model-managed sampling and thinking controls.", language: language)
    }
    package static var claudeMessagesRequired: String {
        VyronSharedResources.current.string("modelDataClaudeMessagesRequired", fallback: "Claude requires at least one conversation message.")
    }

    package static func claudeMessagesRequired(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeMessagesRequired", fallback: "Claude requires at least one conversation message.", language: language)
    }
    package static var claudeNoAnswerOrTool: String {
        VyronSharedResources.current.string("modelDataClaudeNoAnswerOrTool", fallback: "Claude returned no visible answer or tool call.")
    }

    package static func claudeNoAnswerOrTool(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeNoAnswerOrTool", fallback: "Claude returned no visible answer or tool call.", language: language)
    }
    package static var claudeResponseTooLarge: String {
        VyronSharedResources.current.string("modelDataClaudeResponseTooLarge", fallback: "The Claude response is too large.")
    }

    package static func claudeResponseTooLarge(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeResponseTooLarge", fallback: "The Claude response is too large.", language: language)
    }
    package static var claudeStreamError: String {
        VyronSharedResources.current.string("modelDataClaudeStreamError", fallback: "Claude reported a response stream error.")
    }

    package static func claudeStreamError(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeStreamError", fallback: "Claude reported a response stream error.", language: language)
    }
    package static var claudeStreamIncomplete: String {
        VyronSharedResources.current.string("modelDataClaudeStreamIncomplete", fallback: "The Claude response stream ended before completion.")
    }

    package static func claudeStreamIncomplete(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeStreamIncomplete", fallback: "The Claude response stream ended before completion.", language: language)
    }
    package static var claudeStreamTooLarge: String {
        VyronSharedResources.current.string("modelDataClaudeStreamTooLarge", fallback: "The Claude response stream is too large.")
    }

    package static func claudeStreamTooLarge(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeStreamTooLarge", fallback: "The Claude response stream is too large.", language: language)
    }
    package static var claudeToolArgumentsTooLarge: String {
        VyronSharedResources.current.string("modelDataClaudeToolArgumentsTooLarge", fallback: "Claude returned oversized native tool arguments.")
    }

    package static func claudeToolArgumentsTooLarge(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeToolArgumentsTooLarge", fallback: "Claude returned oversized native tool arguments.", language: language)
    }
    package static var claudeTooManyCatalogPages: String {
        VyronSharedResources.current.string("modelDataClaudeTooManyCatalogPages", fallback: "The Claude model list has too many pages.")
    }

    package static func claudeTooManyCatalogPages(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeTooManyCatalogPages", fallback: "The Claude model list has too many pages.", language: language)
    }
    package static var claudeUnsupportedContent: String {
        VyronSharedResources.current.string("modelDataClaudeUnsupportedContent", fallback: "Claude returned an unsupported content block.")
    }

    package static func claudeUnsupportedContent(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeUnsupportedContent", fallback: "Claude returned an unsupported content block.", language: language)
    }
    package static var claudeUnsupportedRole: String {
        VyronSharedResources.current.string("modelDataClaudeUnsupportedRole", fallback: "Unsupported Claude message role.")
    }

    package static func claudeUnsupportedRole(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataClaudeUnsupportedRole", fallback: "Unsupported Claude message role.", language: language)
    }
    package static var connectionFileTooLarge: String {
        VyronSharedResources.current.string("modelDataConnectionFileTooLarge", fallback: "The saved model connections file is too large.")
    }

    package static func connectionFileTooLarge(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataConnectionFileTooLarge", fallback: "The saved model connections file is too large.", language: language)
    }
    package static func connectionNameLimit(_ p1: Int, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDataConnectionNameLimit",
            fallback: "Give this connection a name of at most %ld characters.",
            arguments: [p1],
            language: language
        )
    }
    package static var connectionThinkingUnavailable: String {
        VyronSharedResources.current.string("modelDataConnectionThinkingUnavailable", fallback: "Thinking controls are unavailable for this server and model selection.")
    }

    package static func connectionThinkingUnavailable(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataConnectionThinkingUnavailable", fallback: "Thinking controls are unavailable for this server and model selection.", language: language)
    }
    package static var credentialUnavailable: String {
        VyronSharedResources.current.string("modelDataCredentialUnavailable", fallback: "The model API key could not be accessed in Keychain. Unlock your login keychain or enter the key again.")
    }

    package static func credentialUnavailable(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataCredentialUnavailable", fallback: "The model API key could not be accessed in Keychain. Unlock your login keychain or enter the key again.", language: language)
    }
    package static var deepSeekInvalidToolExchange: String {
        VyronSharedResources.current.string("modelDataDeepSeekInvalidToolExchange", fallback: "The saved DeepSeek tool exchange is invalid or too large.")
    }

    package static func deepSeekInvalidToolExchange(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataDeepSeekInvalidToolExchange", fallback: "The saved DeepSeek tool exchange is invalid or too large.", language: language)
    }
    package static var duplicateOrTooManyConnections: String {
        VyronSharedResources.current.string("modelDataDuplicateOrTooManyConnections", fallback: "Saved model connections contain duplicate profiles or too many connections.")
    }

    package static func duplicateOrTooManyConnections(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataDuplicateOrTooManyConnections", fallback: "Saved model connections contain duplicate profiles or too many connections.", language: language)
    }
    package static var emptyToolResponse: String {
        VyronSharedResources.current.string("modelDataEmptyToolResponse", fallback: "The tool response contains no calls.")
    }

    package static func emptyToolResponse(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataEmptyToolResponse", fallback: "The tool response contains no calls.", language: language)
    }
    package static var inconsistentStreamAnswer: String {
        VyronSharedResources.current.string("modelDataInconsistentStreamAnswer", fallback: "The response stream did not finish with a consistent text answer.")
    }

    package static func inconsistentStreamAnswer(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataInconsistentStreamAnswer", fallback: "The response stream did not finish with a consistent text answer.", language: language)
    }
    package static var inputTokenResponseTooLarge: String {
        VyronSharedResources.current.string("modelDataInputTokenResponseTooLarge", fallback: "The input token count response is too large.")
    }

    package static func inputTokenResponseTooLarge(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataInputTokenResponseTooLarge", fallback: "The input token count response is too large.", language: language)
    }
    package static var interimCommentaryWithoutAnswer: String {
        VyronSharedResources.current.string("modelDataInterimCommentaryWithoutAnswer", fallback: "The model returned interim commentary without a final answer or tool call.")
    }

    package static func interimCommentaryWithoutAnswer(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataInterimCommentaryWithoutAnswer", fallback: "The model returned interim commentary without a final answer or tool call.", language: language)
    }
}
