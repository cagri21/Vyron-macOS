import VyronCore

extension AppModel {
    var canSelectDevelopmentEffort: Bool {
        canManageModelSelection && !modelDownloads.isActive
    }

    @discardableResult
    func selectDevelopmentEffort(_ effort: AgentEffort) -> Bool {
        guard canSelectDevelopmentEffort else { return false }
        composer.effort = effort
        return true
    }
}
