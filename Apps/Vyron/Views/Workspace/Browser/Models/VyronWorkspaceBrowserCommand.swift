enum VyronWorkspaceBrowserCommand: Equatable, Sendable {
    case navigate(VyronWorkspaceBrowserLocation)
    case back
    case forward
    case reload
    case stop
}
