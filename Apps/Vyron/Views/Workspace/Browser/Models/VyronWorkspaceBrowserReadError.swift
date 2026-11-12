import Foundation

struct VyronWorkspaceBrowserReadError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
