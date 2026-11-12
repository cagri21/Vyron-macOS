import Combine
import VyronCore

@MainActor
final class VyronSidebarState: ObservableObject {
    @Published var sidebarOrganization = SidebarOrganization()
    @Published var sidebarSearchText = ""

    let sidebarStore: SidebarOrganizationStore
    var lastSidebarError: String?

    init(store: SidebarOrganizationStore) {
        sidebarStore = store
    }
}
