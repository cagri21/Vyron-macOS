import Foundation
import VyronCore
import VyronModelDomain

extension AppModel {
    func startComputerWork(
        prompt: String,
        effort: AgentEffort,
        response: VyronResponseIdentity
    ) {
        guard foregroundRun.activeResponse == response else { return }
        guard foregroundRun.developmentResponse == nil else {
            updateMessage(
                conversationID: response.conversationID, messageID: response.messageID,
                content: VyronControlText.stopBeforeManual
            )
            finishGeneration(response.generationID, activityState: .failed)
            return
        }
        guard prompt.count <= VyronTaskPromptLimits.maximumCharacters else {
            updateMessage(
                conversationID: response.conversationID, messageID: response.messageID,
                content: VyronControlText.taskDescriptionLimit(VyronTaskPromptLimits.localizedMaximumCharacters)
            )
            finishGeneration(response.generationID, activityState: .failed)
            return
        }
        guard modelSelection.isBuiltinConnection else {
            updateMessage(
                conversationID: response.conversationID, messageID: response.messageID,
                content: VyronControlText.builtinRequired
            )
            finishGeneration(response.generationID, activityState: .failed)
            return
        }
        let goal = PendingAgentGoal(
            goal: prompt, effort: effort,
            conversationID: response.conversationID, messageID: response.messageID
        )
        computerWork.agentConversation = goal
        computerWork.isComputerWorkActive = true
        foregroundRun.complete(response.generationID)
        voice.generationID = nil
        computerWork.pendingAgentGoal = goal
        statusMessage = VyronControlText.startingComputerTask
        recordActivity(
            VyronControlText.startingComputerTask,
            conversationID: response.conversationID, messageID: response.messageID
        )
        appNavigation.showAutomation = true
    }

    func agentGoalStarted(_ requestID: UUID) {
        guard !isShuttingDown, computerWork.agentConversation?.id == requestID else { return }
        if computerWork.pendingAgentGoal?.id == requestID { computerWork.pendingAgentGoal = nil }
    }

    func canStartAgentGoal(_ requestID: UUID) -> Bool {
        !isShuttingDown && computerWork.isComputerWorkActive && computerWork.agentConversation?.id == requestID
    }

    func reportAgentProgress(requestID: UUID, state: String, trace: [String], finished: Bool) {
        guard let active = computerWork.agentConversation, active.id == requestID else { return }
        let recentTrace = trace.suffix(VyronComputerWorkTraceLimits.visibleEntries)
            .map { "- " + String($0.prefix(VyronComputerWorkTraceLimits.entryCharacters)) }
            .joined(separator: "\n")
        let content = state
            + (recentTrace.isEmpty ? "" : "\n\n**\(VyronStatusText.agentTraceHeading)**\n" + recentTrace)
        updateMessage(conversationID: active.conversationID, messageID: active.messageID, content: content)
        statusMessage = state
        if let ci = conversations.firstIndex(where: { $0.id == active.conversationID }),
            let mi = conversations[ci].messages.firstIndex(where: { $0.id == active.messageID }),
            conversations[ci].messages[mi].activity?.state == .working {
            conversations[ci].messages[mi].activity?.record(state, detail: trace.last)
        }
        if finished {
            finishComputerActivity(requestID: requestID, state: .completed)
            computerWork.pendingAgentGoal = nil
            computerWork.agentConversation = nil
            computerWork.isComputerWorkActive = false
            computerWork.isPlanningControls = false
            finishQueuedMessageRun(automaticallyContinue: true)
        }
        saveHistory()
    }

    func finishComputerActivity(requestID: UUID, state: ResponseActivity.State) {
        guard let active = computerWork.agentConversation, active.id == requestID,
            let ci = conversations.firstIndex(where: { $0.id == active.conversationID }),
            let mi = conversations[ci].messages.firstIndex(where: { $0.id == active.messageID }),
            conversations[ci].messages[mi].activity?.state == .working
        else { return }
        conversations[ci].messages[mi].activity?.finish(state)
        saveHistory()
    }
}
