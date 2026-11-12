struct VyronDevelopmentCheckResult: Codable, Sendable, Equatable {
    let exitCode: Int32
    let timedOut: Bool

    var succeeded: Bool { exitCode == 0 && !timedOut }
}
