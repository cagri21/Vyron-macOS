// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronScreenshotText {
    static var preview: String {
        VyronResourceBundle.string("screenshotPreview", fallback: "Preview image")
    }
    static func previewImage(_ p1: String) -> String {
        VyronResourceBundle.format(
            "screenshotPreviewImage",
            fallback: "Preview %@",
            arguments: [p1]
        )
    }
    static func privacyHint(_ p1: String) -> String {
        VyronResourceBundle.format(
            "screenshotPrivacyHint",
            fallback: "Images stay in the draft until Send and are saved in this chat’s history. Your model connection (%@) receives images or locally extracted text, depending on image support.",
            arguments: [p1]
        )
    }
    static var promptTooLong: String {
        VyronResourceBundle.string("screenshotPromptTooLong", fallback: "This message and its images exceed the analysis context limit. Shorten the message or attach fewer images; your draft is preserved.")
    }
    static var readyToAnalyze: String {
        VyronResourceBundle.string("screenshotReadyToAnalyze", fallback: "Image attached. Describe what to inspect, compare, explain, or build, then send.")
    }
    static var refresh: String {
        VyronResourceBundle.string("screenshotRefresh", fallback: "Refresh")
    }
    static var remove: String {
        VyronResourceBundle.string("screenshotRemove", fallback: "Remove image")
    }
    static func removeImage(_ p1: String) -> String {
        VyronResourceBundle.format(
            "screenshotRemoveImage",
            fallback: "Remove %@",
            arguments: [p1]
        )
    }
    static var requestTooLarge: String {
        VyronResourceBundle.string("screenshotRequestTooLarge", fallback: "The attached images exceed 16 MB. Use smaller images or start a new chat.")
    }
    static var saveImage: String {
        VyronResourceBundle.string("screenshotSaveImage", fallback: "Save image…")
    }
    static var selectionRequired: String {
        VyronResourceBundle.string("screenshotSelectionRequired", fallback: "Choose a window or display.")
    }
    static var sourceUnavailable: String {
        VyronResourceBundle.string("screenshotSourceUnavailable", fallback: "This window or display is no longer available. Refresh and choose it again.")
    }
    static var textRecognitionFailed: String {
        VyronResourceBundle.string("screenshotTextRecognitionFailed", fallback: "Could not read text from an attached image on this Mac. Try another image or choose a model with image support.")
    }
    static var tooManyImages: String {
        VyronResourceBundle.string("screenshotTooManyImages", fallback: "Attach up to four images in one request. Remove older images or start a new chat.")
    }
    static var unsupportedFormat: String {
        VyronResourceBundle.string("screenshotUnsupportedFormat", fallback: "Attach a PNG, JPEG, or WebP image with matching image data.")
    }
    static var visionRequired: String {
        VyronResourceBundle.string("screenshotVisionRequired", fallback: "Choose a model that supports images. The selected model does not advertise vision support.")
    }
    static var visionUnsupported: String {
        VyronResourceBundle.string("screenshotVisionUnsupported", fallback: "This model does not advertise image understanding. Choose a model with vision support, then send your screenshot again.")
    }
    static var windowKind: String {
        VyronResourceBundle.string("screenshotWindowKind", fallback: "Window")
    }
}
