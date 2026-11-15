import Foundation
import VyronAutomation
import VyronCore
import VyronModelDomain

extension AppModel {
    func startComputerWork(
        prompt: String,
        effort: AgentEffort,
        response: VyronResponseIdentity
    ) {
        guard foregroundRun.activeResponse == response else { return }
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

    func directChatApplication(for prompt: String) -> DesktopApplication? {
        guard !isRunningScheduledTask, prompt.count <= VyronTaskPromptLimits.maximumCharacters,
            !modelSelection.isBuiltinConnection || foregroundRun.developmentResponse != nil
        else { return nil }
        return VyronChatAppOpenRequest.resolve(
            prompt, applications: computerWork.macWorkController.availableApplications()
        )
    }

    func openChatApplication(
        _ app: DesktopApplication, prompt: String, response: VyronResponseIdentity
    ) async throws {
        recordActivity(
            VyronControlText.startingComputerTask, detail: app.name,
            conversationID: response.conversationID, messageID: response.messageID
        )
        let run = makeMacWorkRun(
            context: VyronMacWorkContext(goal: prompt, projectRoot: nil, allowsActions: true),
            response: response, allowsBackgroundChat: true
        )
        let result: DevelopmentExternalResult
        if let current = VyronChatAppOpenRequest.resolve(
            prompt, applications: computerWork.macWorkController.availableApplications()
        ), current.id == app.id {
            result = try await run.execute(DevelopmentToolCall(
                name: VyronMacWorkTools.openApp, arguments: ["application_id": .string(app.id)]
            ))
        } else {
            result = DevelopmentExternalResult(text: VyronToolsText.openFailed, isError: true)
        }
        try Task.checkCancellation()
        guard foregroundRun.owns(response) else { return }
        updateMessage(
            conversationID: response.conversationID, messageID: response.messageID,
            content: result.isError ? result.text : VyronControlText.actionOpen
        )
        finishConversationResponse(
            response, activityState: result.isError ? .failed : .completed, detail: app.name
        )
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
