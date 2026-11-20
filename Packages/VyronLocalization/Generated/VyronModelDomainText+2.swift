// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

package extension VyronModelDomainText {
    static var controlRejectUnexpectedApplication: String {
        VyronSharedResources.current.string("modelDomainControlRejectUnexpectedApplication", fallback: "The proposal targets a different application.")
    }

    static func controlRejectUnexpectedApplication(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainControlRejectUnexpectedApplication", fallback: "The proposal targets a different application.", language: language)
    }
    static var controlRejectUnsupportedFields: String {
        VyronSharedResources.current.string("modelDomainControlRejectUnsupportedFields", fallback: "Unknown action fields are not supported.")
    }

    static func controlRejectUnsupportedFields(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainControlRejectUnsupportedFields", fallback: "Unknown action fields are not supported.", language: language)
    }
    static var controlRejectUnsupportedNavigationKey: String {
        VyronSharedResources.current.string("modelDomainControlRejectUnsupportedNavigationKey", fallback: "Choose one of the supported navigation keys.")
    }

    static func controlRejectUnsupportedNavigationKey(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainControlRejectUnsupportedNavigationKey", fallback: "Choose one of the supported navigation keys.", language: language)
    }
    static var developmentAlreadyRunning: String {
        VyronSharedResources.current.string("modelDomainDevelopmentAlreadyRunning", fallback: "A development task is already running in this workspace.")
    }

    static func developmentAlreadyRunning(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainDevelopmentAlreadyRunning", fallback: "A development task is already running in this workspace.", language: language)
    }
    static var developmentInvalidGoal: String {
        VyronSharedResources.current.string("modelDomainDevelopmentInvalidGoal", fallback: "Describe the development task.")
    }

    static func developmentInvalidGoal(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainDevelopmentInvalidGoal", fallback: "Describe the development task.", language: language)
    }
    static func developmentInvalidTool(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainDevelopmentInvalidTool",
            fallback: "The development tool request could not be used. %@",
            arguments: [p1],
            language: language
        )
    }
    static var developmentNoCodingModel: String {
        VyronSharedResources.current.string("modelDomainDevelopmentNoCodingModel", fallback: "No compatible local coding model is available. Download a coding model from Local AI Setup.")
    }

    static func developmentNoCodingModel(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainDevelopmentNoCodingModel", fallback: "No compatible local coding model is available. Download a coding model from Local AI Setup.", language: language)
    }
    static func developmentUnsupportedModel(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainDevelopmentUnsupportedModel",
            fallback: "The selected model cannot run this development task. %@",
            arguments: [p1],
            language: language
        )
    }
    static var fileListingRequest: String {
        VyronSharedResources.current.string("modelDomainFileListingRequest", fallback: "Use a file-list limit from 1 to 300, an offset from 0 to 2000, and a nonempty path filter up to 500 UTF-8 bytes.")
    }

    static func fileListingRequest(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainFileListingRequest", fallback: "Use a file-list limit from 1 to 300, an offset from 0 to 2000, and a nonempty path filter up to 500 UTF-8 bytes.", language: language)
    }
    static var fileReadOffset: String {
        VyronSharedResources.current.string("modelDomainFileReadOffset", fallback: "Use a valid UTF-8 file offset and the next offset returned by the previous read.")
    }

    static func fileReadOffset(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainFileReadOffset", fallback: "Use a valid UTF-8 file offset and the next offset returned by the previous read.", language: language)
    }
    static var imageInvalidRole: String {
        VyronSharedResources.current.string("modelDomainImageInvalidRole", fallback: "Images can only be attached to user messages.")
    }

    static func imageInvalidRole(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainImageInvalidRole", fallback: "Images can only be attached to user messages.", language: language)
    }
    static func imageInvalidSize(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainImageInvalidSize",
            fallback: "Each image must contain data and be no larger than %@ MB.",
            arguments: [p1],
            language: language
        )
    }
    static func imageRequestTooLarge(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainImageRequestTooLarge",
            fallback: "The attached images exceed %@ MB. Use smaller images or start a new chat.",
            arguments: [p1],
            language: language
        )
    }
    static var imageTooMany: String {
        VyronSharedResources.current.string("modelDomainImageTooMany", fallback: "Attach up to four images in one request. Remove older images or start a new chat.")
    }

    static func imageTooMany(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainImageTooMany", fallback: "Attach up to four images in one request. Remove older images or start a new chat.", language: language)
    }
    static var imageUnsupportedFormat: String {
        VyronSharedResources.current.string("modelDomainImageUnsupportedFormat", fallback: "Attach a PNG, JPEG, or WebP image with matching image data.")
    }

    static func imageUnsupportedFormat(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainImageUnsupportedFormat", fallback: "Attach a PNG, JPEG, or WebP image with matching image data.", language: language)
    }
    static var imageVisionUnsupported: String {
        VyronSharedResources.current.string("modelDomainImageVisionUnsupported", fallback: "This model does not advertise image understanding. Choose a model with vision support.")
    }

    static func imageVisionUnsupported(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainImageVisionUnsupported", fallback: "This model does not advertise image understanding. Choose a model with vision support.", language: language)
    }
    static var ocrNoText: String {
        VyronSharedResources.current.string("modelDomainOCRNoText", fallback: "No text could be read from these images. Try a clearer image or choose a model with vision support.")
    }

    static func ocrNoText(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainOCRNoText", fallback: "No text could be read from these images. Try a clearer image or choose a model with vision support.", language: language)
    }
    static var ocrRecognitionFailed: String {
        VyronSharedResources.current.string("modelDomainOCRRecognitionFailed", fallback: "Text recognition on this Mac failed. Try another image or choose a model with vision support.")
    }

    static func ocrRecognitionFailed(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainOCRRecognitionFailed", fallback: "Text recognition on this Mac failed. Try another image or choose a model with vision support.", language: language)
    }
    static var ocrTextTooLong: String {
        VyronSharedResources.current.string("modelDomainOCRTextTooLong", fallback: "The text in these images exceeds the OCR limit. Crop the images or attach fewer images.")
    }

    static func ocrTextTooLong(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainOCRTextTooLong", fallback: "The text in these images exceeds the OCR limit. Crop the images or attach fewer images.", language: language)
    }
    static var ollamaCloudModelNotAllowed: String {
        VyronSharedResources.current.string("modelDomainOllamaCloudModelNotAllowed", fallback: "Cloud models are disabled. Choose a model downloaded to this Mac.")
    }

    static func ollamaCloudModelNotAllowed(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainOllamaCloudModelNotAllowed", fallback: "Cloud models are disabled. Choose a model downloaded to this Mac.", language: language)
    }
    static var ollamaConnectionFailed: String {
        VyronSharedResources.current.string("modelDomainOllamaConnectionFailed", fallback: "Cannot connect to local Ollama. Start Ollama on this Mac and try again.")
    }

    static func ollamaConnectionFailed(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainOllamaConnectionFailed", fallback: "Cannot connect to local Ollama. Start Ollama on this Mac and try again.", language: language)
    }
    static func ollamaHTTPDetail(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainOllamaHTTPDetail",
            fallback: "Local Ollama: %@",
            arguments: [p1],
            language: language
        )
    }
    static func ollamaHTTPError(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainOllamaHTTPError",
            fallback: "Local Ollama returned error %@.",
            arguments: [p1],
            language: language
        )
    }
    static var ollamaIncompleteStream: String {
        VyronSharedResources.current.string("modelDomainOllamaIncompleteStream", fallback: "Ollama stopped responding before the result was complete. Try again.")
    }

    static func ollamaIncompleteStream(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainOllamaIncompleteStream", fallback: "Ollama stopped responding before the result was complete. Try again.", language: language)
    }
    static var ollamaInvalidEndpoint: String {
        VyronSharedResources.current.string("modelDomainOllamaInvalidEndpoint", fallback: "Vyron connects only to Ollama on this Mac at http://127.0.0.1.")
    }

    static func ollamaInvalidEndpoint(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainOllamaInvalidEndpoint", fallback: "Vyron connects only to Ollama on this Mac at http://127.0.0.1.", language: language)
    }
    static var ollamaInvalidModelName: String {
        VyronSharedResources.current.string("modelDomainOllamaInvalidModelName", fallback: "Enter a local Ollama model name, such as qwen3-coder:30b.")
    }

    static func ollamaInvalidModelName(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainOllamaInvalidModelName", fallback: "Enter a local Ollama model name, such as qwen3-coder:30b.", language: language)
    }
    static func ollamaInvalidResponse(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainOllamaInvalidResponse",
            fallback: "Could not read the local Ollama response. %@",
            arguments: [p1],
            language: language
        )
    }
    static func ollamaModelNotInstalled(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainOllamaModelNotInstalled",
            fallback: "The model %@ is not downloaded to this Mac.",
            arguments: [p1],
            language: language
        )
    }
    static var ollamaRequestTimedOut: String {
        VyronSharedResources.current.string("modelDomainOllamaRequestTimedOut", fallback: "Ollama request timed out.")
    }

    static func ollamaRequestTimedOut(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainOllamaRequestTimedOut", fallback: "Ollama request timed out.", language: language)
    }
    static var partialReadScope: String {
        VyronSharedResources.current.string("modelDomainPartialReadScope", fallback: "Read source excerpts (partial list; review incomplete):")
    }

    static func partialReadScope(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainPartialReadScope", fallback: "Read source excerpts (partial list; review incomplete):", language: language)
    }
    static var providerAccessRejected: String {
        VyronSharedResources.current.string("modelDomainProviderAccessRejected", fallback: "The model server rejected access. Check the API key and permissions.")
    }

    static func providerAccessRejected(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainProviderAccessRejected", fallback: "The model server rejected access. Check the API key and permissions.", language: language)
    }
    static var providerConnectionFailed: String {
        VyronSharedResources.current.string("modelDomainProviderConnectionFailed", fallback: "Could not connect to the model server. Check its address and whether it is running.")
    }

    static func providerConnectionFailed(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainProviderConnectionFailed", fallback: "Could not connect to the model server. Check its address and whether it is running.", language: language)
    }
    static func providerHTTPError(_ p1: String, language: VyronResourceLanguage? = nil) -> String {
        VyronSharedResources.current.format(
            "modelDomainProviderHTTPError",
            fallback: "The model server returned HTTP %@. Check the connection and supported API.",
            arguments: [p1],
            language: language
        )
    }
    static var providerInvalidEndpoint: String {
        VyronSharedResources.current.string("modelDomainProviderInvalidEndpoint", fallback: "Enter an HTTPS server URL, or an HTTP URL on this Mac, without credentials, query parameters or fragments.")
    }

    static func providerInvalidEndpoint(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainProviderInvalidEndpoint", fallback: "Enter an HTTPS server URL, or an HTTP URL on this Mac, without credentials, query parameters or fragments.", language: language)
    }
    static var providerInvalidModel: String {
        VyronSharedResources.current.string("modelDomainProviderInvalidModel", fallback: "Enter a model ID without spaces or control characters.")
    }

    static func providerInvalidModel(language: VyronResourceLanguage) -> String {
        VyronSharedResources.current.string("modelDomainProviderInvalidModel", fallback: "Enter a model ID without spaces or control characters.", language: language)
    }
}
