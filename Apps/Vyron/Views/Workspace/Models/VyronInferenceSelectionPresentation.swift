import VyronCore

enum VyronInferenceSelectionPresentation {
    static func modelName(_ name: String, automatic: Bool) -> String {
        guard !name.isEmpty else { return VyronWorkspaceText.automaticModel }
        return automatic ? VyronWorkspaceText.automaticSelectedModel(name) : name
    }

    static func speedTitle(_ speed: VyronResponseSpeed) -> String {
        speed == .fast ? VyronWorkspaceText.fastSpeed : VyronWorkspaceText.standardSpeed
    }

    static func summary(model: String, effort: AgentEffort, speed: VyronResponseSpeed) -> String {
        VyronWorkspaceText.inferenceSelection(model, VyronEffortPresentation.title(effort), speedTitle(speed))
    }
}
