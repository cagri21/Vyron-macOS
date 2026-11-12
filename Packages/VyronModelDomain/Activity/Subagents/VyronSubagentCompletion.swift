public struct VyronSubagentCompletion: Codable, Sendable, Equatable {
    public let state: ResponseActivity.State
    public let summary: String

    public init(state: ResponseActivity.State, summary: String) {
        self.state = state
        self.summary = summary
    }
}
