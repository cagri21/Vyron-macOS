public struct VyronImageTextFailureDiagnostic: Sendable, Equatable {
    public let domain: String
    public let code: Int

    public init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }
}
