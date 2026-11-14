import Foundation
import VyronCore

extension AppModel {
    func isResponseActivityLive(messageID: UUID) -> Bool {
        guard let conversationID = selectedConversationID else { return false }
        return isResponseActivityLive(conversationID: conversationID, messageID: messageID)
    }

    func isResponseActivityLive(conversationID: UUID, messageID: UUID) -> Bool {
        guard let conversation = sideChatConversation(with: conversationID),
            conversation.messages.first(where: { $0.id == messageID })?.activity?.state == .working
        else { return false }
        if isSideChatResponseLive(conversationID: conversationID, messageID: messageID) { return true }
        if foregroundRun.response(in: conversationID)?.messageID == messageID { return true }
        if computerWork.isComputerWorkActive, computerWork.agentConversation?.conversationID == conversationID,
            computerWork.agentConversation?.messageID == messageID {
            return true
        }
        guard isRunningScheduledTask, let taskID = scheduledTasks.activeTaskID,
            let run = scheduledTasks.tasks.first(where: { $0.id == taskID })?.progress.lastRun,
            run.output.conversationID == conversationID, conversation.messages.last?.id == messageID
        else { return false }
        return true
    }

    func leaveForegroundConversation() {
        guard foregroundRun.moveResponseToBackground() else {
            stopGeneration()
            return
        }
        voice.end(cancelResponse: false)
        stopQueuedMessageDelivery()
        followUpQuestions.cancel()
    }

    func stopGeneration() {
        voice.end(cancelResponse: false)
        voice.generationID = nil
        stopQueuedMessageDelivery()
        followUpQuestions.cancel()
        if computerWork.isComputerWorkActive {
            if let active = computerWork.agentConversation { finishComputerActivity(requestID: active.id, state: .stopped) }
            computerWork.stopAutomation?()
            if let active = computerWork.agentConversation {
                reportAgentProgress(
                    requestID: active.id,
                    state: VyronStatusText.computerWorkStopped,
                    trace: [],
                    finished: true
                )
            }
            computerWork.pendingAgentGoal = nil
            computerWork.agentConversation = nil
            computerWork.isComputerWorkActive = false
            computerWork.isPlanningControls = false
        }
        guard let stoppedResponse = foregroundRun.activeResponse else { return }
        computerWork.macWorkOverlay.clear(owner: stoppedResponse.generationID)
        cancelPendingUserInput(generationID: stoppedResponse.generationID)
        dismissCommandApproval(generationID: stoppedResponse.generationID)
        dismissPendingChatHandoff(generationID: stoppedResponse.generationID)
        connectionBalances.responseCompleted(foregroundRun.activeBalanceConnectionID)
        finishResponseActivity(.stopped, title: VyronStatusText.stoppedByYou, response: stoppedResponse)
        let wasDeveloping = foregroundRun.isDeveloping
        if wasDeveloping {
            updateMessage(
                conversationID: stoppedResponse.conversationID,
                messageID: stoppedResponse.messageID,
                content: VyronStatusText.developmentStoppedReview
            )
            if inspector.showTerminal { inspector.terminalOutput += "\n[Task stopped.]\n" }
            if let project = workspaceState.developmentWorkspace {
                let url = workspaceState.workspaceURL
                Task { await refreshDevelopmentState(project: project, expectedURL: url) }
            }
        }
        let stoppedProject = workspaceState.developmentWorkspace
        let stoppedProjectURL = workspaceState.workspaceURL
        let isSettling = foregroundRun.stop(
            refreshDevelopment: { [weak self] in
                if let stoppedProject {
                    await self?.refreshDevelopmentState(project: stoppedProject, expectedURL: stoppedProjectURL)
                }
            },
            didSettle: { [weak self] in
                guard let self, !isShuttingDown, selectedConversationID == stoppedResponse.conversationID else { return }
                statusMessage = VyronStatusText.developmentStopped
            }
        )
        if let index = conversations.firstIndex(where: { $0.id == stoppedResponse.conversationID }) {
            conversations[index].messages.removeAll {
                $0.id == stoppedResponse.messageID && $0.conversationRole == .assistant
                    && $0.content.isEmpty && $0.activity == nil
            }
        }
        statusMessage = isSettling ? VyronStatusText.stoppingDevelopment : VyronStatusText.responseStoppedSaved
        saveHistory()
    }

    func appendToken(_ token: String, conversationID: UUID, messageID: UUID) {
        guard let ci = conversations.firstIndex(where: { $0.id == conversationID }),
            let mi = conversations[ci].messages.firstIndex(where: { $0.id == messageID })
        else { return }
        if conversations[ci].messages[mi].content.isEmpty {
            conversations[ci].messages[mi].activity?.record(VyronStatusText.writingResponse)
        }
        conversations[ci].messages[mi].content += token
    }

    func requestSuggestedQuestions(
        using provider: any ModelProvider,
        request: VyronConversationFollowUpRequest
    ) {
        guard !isShuttingDown, !Task.isCancelled else {
            followUpQuestions.cancel()
            return
        }
        followUpQuestions.start(using: provider, request: request) { [weak self] response, questions in
            guard let self, !self.isShuttingDown,
                let conversation = self.conversations.firstIndex(where: { $0.id == response.conversationID }),
                let message = self.conversations[conversation].messages.firstIndex(where: {
                    $0.id == response.messageID
                }),
                self.conversations[conversation].messages[message].activity?.state == .completed,
                self.conversations[conversation].messages.last?.id == response.messageID
            else { return }
            self.conversations[conversation].messages[message].suggestedQuestions = questions
            self.saveHistory()
        }
    }

    func updateMessage(conversationID: UUID, messageID: UUID, content: String) {
        guard let ci = conversations.firstIndex(where: { $0.id == conversationID }),
            let mi = conversations[ci].messages.firstIndex(where: { $0.id == messageID })
        else { return }
        conversations[ci].messages[mi].content = content
    }

    func recordActivity(
        _ title: String,
        detail: String? = nil,
        conversationID: UUID,
        messageID: UUID
    ) {
        guard let ci = conversations.firstIndex(where: { $0.id == conversationID }),
            let mi = conversations[ci].messages.firstIndex(where: { $0.id == messageID })
        else { return }
        conversations[ci].messages[mi].activity?.record(title, detail: detail)
        saveHistory()
    }

    func finishResponseActivity(
        _ state: ResponseActivity.State,
        title: String,
        detail: String? = nil,
        response: VyronResponseIdentity
    ) {
        guard let ci = conversations.firstIndex(where: { $0.id == response.conversationID }),
            let mi = conversations[ci].messages.firstIndex(where: { $0.id == response.messageID })
        else { return }
        conversations[ci].messages[mi].activity?.record(title, detail: detail)
        conversations[ci].messages[mi].activity?.finish(state)
    }

    func finishConversationResponse(
        _ response: VyronResponseIdentity,
        activityState: ResponseActivity.State = .completed,
        detail: String? = nil
    ) {
        if foregroundRun.activeResponse == response {
            finishGeneration(response.generationID, activityState: activityState, detail: detail)
            return
        }
        guard let run = foregroundRun.removeBackgroundResponse(response) else { return }
        cancelPendingUserInput(generationID: response.generationID)
        dismissCommandApproval(generationID: response.generationID)
        dismissPendingChatHandoff(generationID: response.generationID)
        connectionBalances.responseCompleted(run.balanceConnectionID)
        finishResponseActivity(activityState, title: responseActivityTitle(activityState), detail: detail, response: response)
        conversations.sort { $0.updatedAt > $1.updatedAt }
        saveHistory()
    }

    private func responseActivityTitle(_ state: ResponseActivity.State) -> String {
        switch state {
        case .completed: VyronStatusText.responseReady
        case .stopped: VyronStatusText.responseStopped
        case .failed: VyronStatusText.responseFailed
        case .working: VyronStatusText.writingResponse
        }
    }

    func finishGeneration(
        _ id: UUID,
        activityState: ResponseActivity.State = .completed,
        detail: String? = nil
    ) {
        guard let response = foregroundRun.activeResponse, response.generationID == id else { return }
        connectionBalances.responseCompleted(foregroundRun.activeBalanceConnectionID)
        cancelPendingUserInput(generationID: id)
        dismissCommandApproval(generationID: id)
        let voiceAnswer = voice.generationID == id
            ? conversations.first { $0.id == response.conversationID }?.messages
                .first { $0.id == response.messageID }?.content
            : nil
        finishResponseActivity(
            activityState, title: responseActivityTitle(activityState), detail: detail, response: response
        )
        foregroundRun.complete(id)
        conversations.sort { $0.updatedAt > $1.updatedAt }
        let historySaved = saveHistory()
        let presentedHandoff = presentPendingChatHandoff(
            generationID: id, completed: activityState == .completed && historySaved
        )
        finishQueuedMessageRun(automaticallyContinue: activityState == .completed && !presentedHandoff)
        if voice.generationID == id {
            voice.generationID = nil
            voice.responseFinished(
                answer: voiceAnswer,
                error: activityState == .completed ? nil : detail ?? errorMessage ?? VyronVoiceText.recognitionFailed
            )
        }
    }
}
