package struct VyronDevelopmentInferenceConfiguration: Sendable {
    package let effort: AgentEffort
    package let mode: DevelopmentMode
    package let externalTools: [DevelopmentExternalTool]

    package init(effort: AgentEffort, mode: DevelopmentMode, externalTools: [DevelopmentExternalTool]) {
        self.effort = effort
        self.mode = mode
        self.externalTools = externalTools
    }
}
