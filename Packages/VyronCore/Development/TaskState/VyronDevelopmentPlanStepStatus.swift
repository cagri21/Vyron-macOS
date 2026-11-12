enum VyronDevelopmentPlanStepStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
}
