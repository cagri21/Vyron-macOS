import Foundation

struct VyronWorkspaceBrowserRequest: Equatable, Sendable {
    let id: UUID
    let command: VyronWorkspaceBrowserCommand
}
