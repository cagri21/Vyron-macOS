import Foundation

struct VyronSidebarEntry: Identifiable {
    let id: String
    let kind: VyronSidebarEntryKind
    let depth: Int
}
