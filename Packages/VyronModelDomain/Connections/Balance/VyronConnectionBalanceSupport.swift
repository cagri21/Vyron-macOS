public enum VyronConnectionBalanceSupport: Equatable, Sendable {
    case local
    case unsupported
    case dashboardOnly
    case openRouter
    case deepSeek

    public var canFetch: Bool {
        self == .openRouter || self == .deepSeek
    }
}
