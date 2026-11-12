import Foundation
import VyronCore

extension AppModel {
    func start(readKey: (@Sendable (UUID) async throws -> String)? = nil) async {
        guard canContinueStartup else { return }
        let readCredential: @Sendable (UUID) async throws -> String = readKey ?? { [modelCredentialReader] id in
            try await modelCredentialReader.key(for: id)
        }
        await startup.run { [weak self] in
            guard let self else { return false }
            return await self.prepareStartup(readKey: readCredential)
        }
    }

    private var canContinueStartup: Bool {
        !isShuttingDown && !Task.isCancelled
    }

    private func prepareStartup(readKey: @Sendable (UUID) async throws -> String) async -> Bool {
        guard canContinueStartup else { return false }
        requestLocalCredentialSynchronization()
        await prepareActiveModelConnection(readKey: readKey)
        guard canContinueStartup else { return false }
        connectionBalances.start()
        if let workspaceURL = workspaceState.workspaceURL, workspaceState.developmentWorkspace == nil {
            await loadWorkspace(workspaceURL, projectPath: workspaceState.selectedProjectPath)
        }
        guard canContinueStartup else { return false }
        if modelSelection.isBuiltinConnection { await startEngine() } else { await refreshModels() }
        guard canContinueStartup else { return false }
        startRefreshingModels()
        scheduledTasks.start()
        return true
    }

    func shutdownAsync() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        let starting = startup.shutdown()
        let authenticating = localAuthentication.shutdown()
        connectionBalances.shutdown()
        connectionBalanceSubscriptions.removeAll()
        let sideChats = stopSideChatsForShutdown()
        for response in foregroundRun.backgroundResponseIdentities {
            finishResponseActivity(.stopped, title: VyronStatusText.stoppedOnQuit, response: response)
            if foregroundRun.isDevelopmentResponse(response) {
                updateMessage(
                    conversationID: response.conversationID,
                    messageID: response.messageID,
                    content: VyronStatusText.developmentStoppedOnQuit
                )
            }
        }
        composerAttachments.resetDrafts()
        cancelPendingUserInput()
        voice.end(cancelResponse: false)
        voice.generationID = nil
        stopQueuedMessageDelivery()
        scheduledTasks.shutdown()
        mcpConnections.shutdown()
        let verifying = modelFeatures.verificationTask
        let suggesting = followUpQuestions.cancel()
        modelSelection.shutdown()
        cancelModelFeatureVerification()
        let downloading = modelDownloads.shutdown()
        respondToCommandApproval(false)
        if let response = foregroundRun.activeResponse {
            finishResponseActivity(.stopped, title: VyronStatusText.stoppedOnQuit, response: response)
            if foregroundRun.isDeveloping {
                updateMessage(
                    conversationID: response.conversationID,
                    messageID: response.messageID,
                    content: VyronStatusText.developmentStoppedOnQuit
                )
            }
        }
        computerWork.stopAutomation?()
        computerWork.macWorkOverlay.clear()
        if let active = computerWork.agentConversation {
            reportAgentProgress(
                requestID: active.id,
                state: VyronStatusText.computerWorkStoppedOnQuit,
                trace: [],
                finished: true
            )
        }
        computerWork.pendingAgentGoal = nil
        let foregroundTasks = foregroundRun.shutdown()

        // Let cancellation close the HTTP streams before stopping their server.
        // An unstructured waiter keeps the app's termination deadline bounded.
        let settlement = Task { @MainActor [weak self] in
            await starting?.value
            await authenticating?.value
            for task in foregroundTasks { await task.value }
            await downloading?.value
            await suggesting?.value
            await verifying?.value
            for sideChat in sideChats { await sideChat.value }
            await self?.scheduledTasks.waitForCurrentRun()
            self?.shutdownTasksSettled = true
        }
        for _ in 0..<VyronAppShutdownTiming.settlementPollLimit {
            if shutdownTasksSettled { break }
            try? await Task.sleep(for: VyronAppShutdownTiming.settlementPollInterval)
        }
        settlement.cancel()

        // Ollama saves resumable download metadata after the request disconnects.
        // Keep the owned engine alive briefly so that cleanup reaches disk.
        try? await Task.sleep(for: VyronAppShutdownTiming.runtimeCleanupGracePeriod)
        runtime.stopOwnedRuntime()
        saveHistory()
    }
}
