package struct VyronDevelopmentMessageBudget: Sendable {
    package let workingBytes: Int
    package let maximumBytes: Int

    package init(workingBytes: Int, maximumBytes: Int) {
        self.workingBytes = workingBytes
        self.maximumBytes = maximumBytes
    }

    package static let standard = Self(workingBytes: 20_000, maximumBytes: 24_000)
    package static let maximumToolOutputBytes = 4_000
}
