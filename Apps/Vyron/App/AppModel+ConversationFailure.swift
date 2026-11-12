import Foundation
import VyronCore

extension AppModel {
    func failConversationRun(
        _ error: any Error,
        route: VyronConversationFailureRoute,
        response: VyronResponseIdentity
    ) async {
        guard foregroundRun.owns(response) else { return }
        let isForeground = foregroundRun.activeResponse == response
        if isForeground, !Task.isCancelled {
            let showsLocalContextBudgetHelp = if case .project = route {
                modelSelection.isBuiltinConnection && (error as? DevelopmentAgentError) == .contextBudget
            } else {
                false
            }
            workspaceError = VyronWorkspaceError(
                message: VyronScreenshotErrorPresentation.description(error),
                showsLocalContextBudgetHelp: showsLocalContextBudgetHelp
            )
        }
        if isForeground { statusMessage = VyronStatusText.stoppedWithError }
        let content: String?
        switch route {
        case .compaction:
            content = VyronCompactionText.failed
        case .project(let project):
            if isForeground { await refreshDevelopmentState(project: project.workspace, expectedURL: project.url) }
            guard foregroundRun.owns(response), !Task.isCancelled else { return }
            content = VyronStatusText.developmentFailed(error.localizedDescription)
        case .webSearch:
            content = Task.isCancelled ? nil : VyronControlText.webLookupFailed(error.localizedDescription)
        case .chat:
            content = nil
        }
        if let content {
            updateMessage(conversationID: response.conversationID, messageID: response.messageID, content: content)
        }
        finishConversationResponse(
            response,
            activityState: Task.isCancelled ? .stopped : .failed,
            detail: error.localizedDescription
        )
    }
}
