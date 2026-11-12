import VyronDevelopment

extension VyronDevelopmentRunProgress {
    var canMoveToProject: Bool {
        state.progress.files.isEmpty && state.progress.checks.isEmpty && state.progress.integrations.isEmpty
            && !state.plan.contains(where: { $0.status == .completed })
    }

    func moved(to workspace: DevelopmentWorkspace, session: VyronDevelopmentSessionContext?) throws -> Self {
        guard canMoveToProject else {
            throw DevelopmentAgentError.invalidTool("Move to the destination project before editing or executing actions.")
        }
        var moved = try Self(moving: state, workspace: workspace, conversationID: session?.conversationID)
        moved.state.recordDecision("Project folder opened at " + workspace.rootURL.path)
        return moved
    }
}
