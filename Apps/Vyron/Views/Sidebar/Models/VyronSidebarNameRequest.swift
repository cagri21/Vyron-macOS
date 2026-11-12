import Foundation

struct VyronSidebarNameRequest: Identifiable {
    let id = UUID()
    let operation: VyronSidebarNameOperation
    let targetID: UUID?
    let title: String
    let initialValue: String
}
