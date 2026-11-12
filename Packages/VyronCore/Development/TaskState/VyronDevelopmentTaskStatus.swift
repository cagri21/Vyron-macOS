enum VyronDevelopmentTaskStatus: String, Codable, Sendable {
    case running
    case interrupted
    case completed
    case stopped
    case failed

    var isFinished: Bool { self == .completed }
}
