// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

package extension VyronModelDataText {
    static var ollamaStructuredResponseUnavailable: String {
        VyronSharedResources.current.string("modelDataOllamaStructuredResponseUnavailable", fallback: "The local structured response was unavailable.")
    }

    static func ollamaStructuredResponseUnavailable(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataOllamaStructuredResponseUnavailable", fallback: "The local structured response was unavailable.", language: language)
    }
    static var openAIManagedSampling: String {
        VyronSharedResources.current.string("modelDataOpenAIManagedSampling", fallback: "This OpenAI connection uses model-managed sampling. Clear Temperature and Top P to use it.")
    }

    static func openAIManagedSampling(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataOpenAIManagedSampling", fallback: "This OpenAI connection uses model-managed sampling. Clear Temperature and Top P to use it.", language: language)
    }
    static var oversizedResponse: String {
        VyronSharedResources.current.string("modelDataOversizedResponse", fallback: "The response is too large.")
    }

    static func oversizedResponse(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataOversizedResponse", fallback: "The response is too large.", language: language)
    }
    static var reasoningResponseTooLarge: String {
        VyronSharedResources.current.string("modelDataReasoningResponseTooLarge", fallback: "The reasoning response is too large.")
    }

    static func reasoningResponseTooLarge(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataReasoningResponseTooLarge", fallback: "The reasoning response is too large.", language: language)
    }
    static var repeatedToolMarkup: String {
        VyronSharedResources.current.string("modelDataRepeatedToolMarkup", fallback: "The model printed tool markup again instead of making a native tool call. No printed command was executed.")
    }

    static func repeatedToolMarkup(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataRepeatedToolMarkup", fallback: "The model printed tool markup again instead of making a native tool call. No printed command was executed.", language: language)
    }
    static var responseEndedEarly: String {
        VyronSharedResources.current.string("modelDataResponseEndedEarly", fallback: "The response ended before completion.")
    }

    static func responseEndedEarly(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataResponseEndedEarly", fallback: "The response ended before completion.", language: language)
    }
    static var responseLineTooLarge: String {
        VyronSharedResources.current.string("modelDataResponseLineTooLarge", fallback: "Response line is too large.")
    }

    static func responseLineTooLarge(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataResponseLineTooLarge", fallback: "Response line is too large.", language: language)
    }
    static var responseStreamIncomplete: String {
        VyronSharedResources.current.string("modelDataResponseStreamIncomplete", fallback: "The response stream ended before completion.")
    }

    static func responseStreamIncomplete(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataResponseStreamIncomplete", fallback: "The response stream ended before completion.", language: language)
    }
    static var responseStreamTooLarge: String {
        VyronSharedResources.current.string("modelDataResponseStreamTooLarge", fallback: "The response stream is too large.")
    }

    static func responseStreamTooLarge(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataResponseStreamTooLarge", fallback: "The response stream is too large.", language: language)
    }
    static var responseTooLarge: String {
        VyronSharedResources.current.string("modelDataResponseTooLarge", fallback: "Response is too large.")
    }

    static func responseTooLarge(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataResponseTooLarge", fallback: "Response is too large.", language: language)
    }
    static var serverIncompleteAssistantResponse: String {
        VyronSharedResources.current.string("modelDataServerIncompleteAssistantResponse", fallback: "The server did not finish a complete assistant response.")
    }

    static func serverIncompleteAssistantResponse(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataServerIncompleteAssistantResponse", fallback: "The server did not finish a complete assistant response.", language: language)
    }
    static var serverInferenceError: String {
        VyronSharedResources.current.string("modelDataServerInferenceError", fallback: "The server reported an inference error.")
    }

    static func serverInferenceError(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataServerInferenceError", fallback: "The server reported an inference error.", language: language)
    }
    static var serverInvalidNativeToolCall: String {
        VyronSharedResources.current.string("modelDataServerInvalidNativeToolCall", fallback: "The server returned an invalid native tool call.")
    }

    static func serverInvalidNativeToolCall(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataServerInvalidNativeToolCall", fallback: "The server returned an invalid native tool call.", language: language)
    }
    static var serverNoAnswer: String {
        VyronSharedResources.current.string("modelDataServerNoAnswer", fallback: "The server returned no visible answer.")
    }

    static func serverNoAnswer(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataServerNoAnswer", fallback: "The server returned no visible answer.", language: language)
    }
    static var serverNoAnswerOrTool: String {
        VyronSharedResources.current.string("modelDataServerNoAnswerOrTool", fallback: "The server returned no visible answer or tool call.")
    }

    static func serverNoAnswerOrTool(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataServerNoAnswerOrTool", fallback: "The server returned no visible answer or tool call.", language: language)
    }
    static var serverPrintedToolMarkup: String {
        VyronSharedResources.current.string("modelDataServerPrintedToolMarkup", fallback: "The server printed tool markup instead of returning native tool calls. No printed command was executed.")
    }

    static func serverPrintedToolMarkup(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataServerPrintedToolMarkup", fallback: "The server printed tool markup instead of returning native tool calls. No printed command was executed.", language: language)
    }
    static var serverRejectedOutputLimit: String {
        VyronSharedResources.current.string("modelDataServerRejectedOutputLimit", fallback: "The server rejected the output token limit.")
    }

    static func serverRejectedOutputLimit(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataServerRejectedOutputLimit", fallback: "The server rejected the output token limit.", language: language)
    }
    static var serverResponseError: String {
        VyronSharedResources.current.string("modelDataServerResponseError", fallback: "The server reported a response error.")
    }

    static func serverResponseError(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataServerResponseError", fallback: "The server reported a response error.", language: language)
    }
    static var serverStreamError: String {
        VyronSharedResources.current.string("modelDataServerStreamError", fallback: "The server reported a streaming error.")
    }

    static func serverStreamError(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataServerStreamError", fallback: "The server reported a streaming error.", language: language)
    }
    static var sourceArchitectureRejected: String {
        VyronSharedResources.current.string("modelDataSourceArchitectureRejected", fallback: "The runtime rejected this model's architecture or GGUF data. Check Ollama's compatibility with this model.")
    }

    static func sourceArchitectureRejected(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataSourceArchitectureRejected", fallback: "The runtime rejected this model's architecture or GGUF data. Check Ollama's compatibility with this model.", language: language)
    }
    static func sourceHTTPStatus(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDataSourceHTTPStatus",
            fallback: "The model source returned HTTP %@. Check the URL and whether the model is publicly accessible.",
            arguments: [p1],
            language: language
        )
    }
    static func sourceImportFailed(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDataSourceImportFailed",
            fallback: "Ollama could not import the model. %@",
            arguments: [p1],
            language: language
        )
    }
    static var sourceImportIncomplete: String {
        VyronSharedResources.current.string("modelDataSourceImportIncomplete", fallback: "The runtime stopped before confirming success.")
    }

    static func sourceImportIncomplete(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataSourceImportIncomplete", fallback: "The runtime stopped before confirming success.", language: language)
    }
    static var sourceInvalidGGUF: String {
        VyronSharedResources.current.string("modelDataSourceInvalidGGUF", fallback: "The downloaded file is not a supported GGUF model. It may be an HTML page, a Git LFS pointer, or an incomplete download.")
    }

    static func sourceInvalidGGUF(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataSourceInvalidGGUF", fallback: "The downloaded file is not a supported GGUF model. It may be an HTML page, a Git LFS pointer, or an incomplete download.", language: language)
    }
    static var sourceInvalidLocalEndpoint: String {
        VyronSharedResources.current.string("modelDataSourceInvalidLocalEndpoint", fallback: "Model files can be imported only into Ollama running on this Mac.")
    }

    static func sourceInvalidLocalEndpoint(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataSourceInvalidLocalEndpoint", fallback: "Model files can be imported only into Ollama running on this Mac.", language: language)
    }
    static var sourceInvalidMetadata: String {
        VyronSharedResources.current.string("modelDataSourceInvalidMetadata", fallback: "The model source returned unreadable variant information.")
    }

    static func sourceInvalidMetadata(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataSourceInvalidMetadata", fallback: "The model source returned unreadable variant information.", language: language)
    }
    static var sourceInvalidURL: String {
        VyronSharedResources.current.string("modelDataSourceInvalidURL", fallback: "Enter an HTTPS model URL without a username, password, or fragment.")
    }

    static func sourceInvalidURL(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataSourceInvalidURL", fallback: "Enter an HTTPS model URL without a username, password, or fragment.", language: language)
    }
    static var sourceMetadataTooLarge: String {
        VyronSharedResources.current.string("modelDataSourceMetadataTooLarge", fallback: "The source contains too many files. Use a more specific repository folder or a direct GGUF URL.")
    }

    static func sourceMetadataTooLarge(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataSourceMetadataTooLarge", fallback: "The source contains too many files. Use a more specific repository folder or a direct GGUF URL.", language: language)
    }
    static var sourceModelAlreadyExists: String {
        VyronSharedResources.current.string("modelDataSourceModelAlreadyExists", fallback: "That local model name already exists. Choose another name to keep the installed model.")
    }

    static func sourceModelAlreadyExists(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataSourceModelAlreadyExists", fallback: "That local model name already exists. Choose another name to keep the installed model.", language: language)
    }
    static var sourceNoVariants: String {
        VyronSharedResources.current.string("modelDataSourceNoVariants", fallback: "This source did not publish any supported model variants. Try a public GGUF repository or an exact Ollama model tag.")
    }

    static func sourceNoVariants(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataSourceNoVariants", fallback: "This source did not publish any supported model variants. Try a public GGUF repository or an exact Ollama model tag.", language: language)
    }
    static var sourceSplitGGUF: String {
        VyronSharedResources.current.string("modelDataSourceSplitGGUF", fallback: "This is one part of a split GGUF model. Choose a single-file GGUF variant; importing split models is not supported yet.")
    }

    static func sourceSplitGGUF(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataSourceSplitGGUF", fallback: "This is one part of a split GGUF model. Choose a single-file GGUF variant; importing split models is not supported yet.", language: language)
    }
    static var sourceUnsupported: String {
        VyronSharedResources.current.string("modelDataSourceUnsupported", fallback: "Use an Ollama model page, a public Hugging Face GGUF repository, or a direct .gguf download URL.")
    }

    static func sourceUnsupported(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataSourceUnsupported", fallback: "Use an Ollama model page, a public Hugging Face GGUF repository, or a direct .gguf download URL.", language: language)
    }
    static var streamingEventTooLarge: String {
        VyronSharedResources.current.string("modelDataStreamingEventTooLarge", fallback: "Streaming event is too large.")
    }

    static func streamingEventTooLarge(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataStreamingEventTooLarge", fallback: "Streaming event is too large.", language: language)
    }
    static var structuredContextExceeded: String {
        VyronSharedResources.current.string("modelDataStructuredContextExceeded", fallback: "The structured request exceeds the selected model's context budget.")
    }

    static func structuredContextExceeded(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataStructuredContextExceeded", fallback: "The structured request exceeds the selected model's context budget.", language: language)
    }
    static var structuredResponseTooLarge: String {
        VyronSharedResources.current.string("modelDataStructuredResponseTooLarge", fallback: "The structured response is too large.")
    }

    static func structuredResponseTooLarge(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDataStructuredResponseTooLarge", fallback: "The structured response is too large.", language: language)
    }
}
