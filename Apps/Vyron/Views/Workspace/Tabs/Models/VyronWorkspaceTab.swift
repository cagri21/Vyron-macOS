import Foundation

struct VyronWorkspaceTab: Equatable, Identifiable, Sendable {
    let id: UUID
    var location: VyronWorkspaceTabLocation
    var title: String

    var kind: VyronWorkspaceTabKind { location.kind }
    var canClose: Bool { kind != .conversation }
}
