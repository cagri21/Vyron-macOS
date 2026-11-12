struct VyronDevelopmentPlanUpdate: Sendable, Equatable {
    let steps: [VyronDevelopmentPlanStep]
    let explanation: String?

    init(steps: [VyronDevelopmentPlanStep], explanation: String? = nil) {
        self.steps = steps
        self.explanation = explanation
    }
}
