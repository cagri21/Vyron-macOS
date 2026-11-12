enum VyronPluginFilter: CaseIterable, Hashable {
    case all
    case installed
    case connected

    var title: String {
        switch self {
        case .all: VyronPluginText.all
        case .installed: VyronPluginText.installed
        case .connected: VyronPluginText.connected
        }
    }
}
