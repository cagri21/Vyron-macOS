import Foundation

struct VyronModelTransfer: Sendable {
    let id = UUID()
    let tag: String
    let kind: VyronModelTransferKind
}
