enum VyronAutomationPlannerMode: String, CaseIterable {
    case agent
    case oneAction = "one"
    case reviewSteps = "task"

    var title: String {
        switch self {
        case .agent: VyronAppText.automationAgent
        case .oneAction: VyronAppText.automationOneAction
        case .reviewSteps: VyronAppText.automationReviewSteps
        }
    }
}
