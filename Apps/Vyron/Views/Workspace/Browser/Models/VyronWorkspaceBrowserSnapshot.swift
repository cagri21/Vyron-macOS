import Foundation

struct VyronWorkspaceBrowserSnapshot: Equatable, Sendable {
    let url: URL?
    let title: String?
    let canGoBack: Bool
    let canGoForward: Bool
}
