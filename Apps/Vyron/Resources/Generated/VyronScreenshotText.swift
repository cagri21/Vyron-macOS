// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronScreenshotText {
    static var analysisHint: String {
        VyronResourceBundle.string("screenshotAnalysisHint", fallback: "Images use your selected mode and model, including when Auto is on. Choose a model that supports images.")
    }
    static var analysisPrompt: String {
        VyronResourceBundle.string("screenshotAnalysisPrompt", fallback: "Analyze the attached screenshots. Describe what is visible, identify any interface issues, and suggest useful improvements.")
    }
    static var attachmentLimit: String {
        VyronResourceBundle.string("screenshotAttachmentLimit", fallback: "Attach up to four images at a time.")
    }
    static var cancel: String {
        VyronResourceBundle.string("screenshotCancel", fallback: "Cancel")
    }
    static var capture: String {
        VyronResourceBundle.string("screenshotCapture", fallback: "Capture")
    }
    static func captureFailed(_ p1: String) -> String {
        VyronResourceBundle.format(
            "screenshotCaptureFailed",
            fallback: "Could not capture this source. %@",
            arguments: [p1]
        )
    }
    static var capturing: String {
        VyronResourceBundle.string("screenshotCapturing", fallback: "Capturing…")
    }
    static var chatOnly: String {
        VyronResourceBundle.string("screenshotChatOnly", fallback: "Switch to Chat to analyze attached images.")
    }
    static var clipboardEmpty: String {
        VyronResourceBundle.string("screenshotClipboardEmpty", fallback: "The clipboard does not contain an image. Copy an image, then try again.")
    }
    static var close: String {
        VyronResourceBundle.string("screenshotClose", fallback: "Close")
    }
    static var copyFailed: String {
        VyronResourceBundle.string("screenshotCopyFailed", fallback: "Could not copy the image. Try again.")
    }
    static var copyImage: String {
        VyronResourceBundle.string("screenshotCopyImage", fallback: "Copy image")
    }
    static var displayKind: String {
        VyronResourceBundle.string("screenshotDisplayKind", fallback: "Display")
    }
    static func displayName(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "screenshotDisplayName",
            fallback: "Display %d",
            arguments: [p1]
        )
    }
    static var droppedImage: String {
        VyronResourceBundle.string("screenshotDroppedImage", fallback: "Dropped image")
    }
    static var encodingFailed: String {
        VyronResourceBundle.string("screenshotEncodingFailed", fallback: "The screenshot could not be saved as an image. Try again.")
    }
    static var extractedTextTooLong: String {
        VyronResourceBundle.string("screenshotExtractedTextTooLong", fallback: "The extracted image text exceeds the analysis limit. Crop the image or attach fewer images.")
    }
    static var imageTooLarge: String {
        VyronResourceBundle.string("screenshotImageTooLarge", fallback: "This image exceeds the attachment limit. Choose a smaller image or remove an attachment.")
    }
    static var importImages: String {
        VyronResourceBundle.string("screenshotImportImages", fallback: "Attach images…")
    }
    static var importing: String {
        VyronResourceBundle.string("screenshotImporting", fallback: "Preparing images…")
    }
    static var invalidImage: String {
        VyronResourceBundle.string("screenshotInvalidImage", fallback: "This file is not a readable image. Choose a PNG, JPEG, HEIC, or another supported image.")
    }
    static var invalidRole: String {
        VyronResourceBundle.string("screenshotInvalidRole", fallback: "Images can only be attached to user messages.")
    }
    static var invalidSize: String {
        VyronResourceBundle.string("screenshotInvalidSize", fallback: "Each image must contain data and be no larger than 8 MB.")
    }
    static func loadFailed(_ p1: String) -> String {
        VyronResourceBundle.format(
            "screenshotLoadFailed",
            fallback: "Could not list capture sources. %@",
            arguments: [p1]
        )
    }
    static var loading: String {
        VyronResourceBundle.string("screenshotLoading", fallback: "Finding windows and displays…")
    }
    static var localTextHint: String {
        VyronResourceBundle.string("screenshotLocalTextHint", fallback: "Ollama models without image support receive text read on this Mac. Use a model with image support to analyze layout and visual details.")
    }
    static var noReadableText: String {
        VyronResourceBundle.string("screenshotNoReadableText", fallback: "No readable text was found in the attached images. Try a clearer screenshot or choose a model with image support.")
    }
    static var noSources: String {
        VyronResourceBundle.string("screenshotNoSources", fallback: "No available windows or displays. Open the app you want to capture, then refresh.")
    }
    static var openSettings: String {
        VyronResourceBundle.string("screenshotOpenSettings", fallback: "Open Screen Recording Settings")
    }
    static var pastedImage: String {
        VyronResourceBundle.string("screenshotPastedImage", fallback: "Pasted screenshot")
    }
    static var pasteImage: String {
        VyronResourceBundle.string("screenshotPasteImage", fallback: "Paste image")
    }
    static var permissionRequired: String {
        VyronResourceBundle.string("screenshotPermissionRequired", fallback: "Allow Vyron to record your screen in System Settings → Privacy & Security → Screen Recording, then refresh.")
    }
    static var permissionTitle: String {
        VyronResourceBundle.string("screenshotPermissionTitle", fallback: "Allow Screen Recording")
    }
    static var pickerHint: String {
        VyronResourceBundle.string("screenshotPickerHint", fallback: "Choose a window from Simulator, Device Hub, or another app, or capture an entire display.")
    }
    static var pickerTitle: String {
        VyronResourceBundle.string("screenshotPickerTitle", fallback: "Capture a screenshot")
    }
}
