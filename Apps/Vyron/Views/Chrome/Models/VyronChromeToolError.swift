import Foundation

enum VyronChromeToolError: LocalizedError {
    case invalidArguments

    var errorDescription: String? {
        "Invalid Chrome tool arguments. Use session, tab, snapshot, and element IDs returned by the Chrome tools. "
            + "Page changes require interactive Work mode and approval in the Chrome extension."
    }
}
