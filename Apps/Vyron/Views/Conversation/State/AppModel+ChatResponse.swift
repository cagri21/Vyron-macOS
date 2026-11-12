import Foundation
import VyronCore

extension AppModel {
    func runChatResponse(
        _ started: VyronStartedConversationResponse,
        prompt: String,
        references: VyronChatResponseReferences,
        configuration: VyronChatResponseConfiguration
    ) async throws {
        let identity = started.identity
        let inference = configuration.inference
        let model = inference.model
        recordActivity(
            VyronStatusText.preparingContext,
            detail: references.files.isEmpty ? nil : VyronStatusText.selectedFiles(references.files.count),
            conversationID: identity.conversationID,
            messageID: identity.messageID
        )

        var workspaceContext = ""
        if !configuration.usesWebEvidence, let workspace = references.workspace {
            workspaceContext = try await workspace.contextSummary(
                maxFiles: VyronConversationLimits.maximumWorkspaceSummaryFiles
            )
        }
        guard foregroundRun.owns(identity), !Task.isCancelled else { return }
        let projectContext = VyronConversationRequestContext.contextPrompt(
            workspaceContext: workspaceContext,
            files: references.files
        )
        let context = chatResponseContext(for: started, skills: references.skills, project: projectContext.text)
        var history = VyronConversationRequestContext.boundedHistory(
            started.context.history, context: context, compaction: started.context.compaction
        )
        let siteAnalysis: VyronWebsiteAnalysis?
        if configuration.requestKind == .websiteAnalysis {
            let analysis = try await websiteAnalysis(for: prompt, response: identity)
            guard foregroundRun.owns(identity), !Task.isCancelled else { return }
            guard let evidence = analysis.evidence else {
                updateMessage(
                    conversationID: identity.conversationID, messageID: identity.messageID, content: analysis.report
                )
                if foregroundRun.activeResponse == identity { statusMessage = VyronStatusText.stoppedWithError }
                finishConversationResponse(identity, activityState: .failed)
                return
            }
            siteAnalysis = analysis
            history.messages.append(ChatMessage(role: .user, content: evidence))
        } else if configuration.usesWebEvidence {
            siteAnalysis = nil
            let evidence = try await webContext(for: prompt, response: identity)
            guard foregroundRun.owns(identity), !Task.isCancelled else { return }
            history.messages.append(ChatMessage(role: .user, content: evidence))
        } else {
            siteAnalysis = nil
        }
        if foregroundRun.activeResponse == identity,
            history.omittedOlderMessages || projectContext.truncated {
            statusMessage = VyronStatusText.boundedContext
        }
        recordActivity(
            VyronStatusText.requestingResponse,
            detail: VyronStatusText.responseModel(model),
            conversationID: identity.conversationID,
            messageID: identity.messageID
        )
        let systemPrompt = configuration.mode == .plan
            ? VyronConversationRequestContext.planSystemPrompt : VyronConversationRequestContext.systemPrompt
        let request = VyronChatInferenceRequest(
            model: model,
            messages: history.messages,
            configuration: .init(
                systemPrompt: systemPrompt
                    + (configuration.usesWebEvidence ? VyronConversationRequestContext.webSystemPrompt : "")
                    + (siteAnalysis == nil ? "" : VyronConversationRequestContext.websiteAnalysisSystemPrompt),
                effort: inference.effort
            )
        )
        let answer = try await streamConversationReply(using: inference.provider, request: request, response: identity)
        guard foregroundRun.owns(identity), !Task.isCancelled else { return }
        let finalAnswer = siteAnalysis.map { answer + "\n\n" + $0.report } ?? answer
        updateMessage(conversationID: identity.conversationID, messageID: identity.messageID, content: finalAnswer)
        let isForeground = foregroundRun.activeResponse == identity
        if isForeground {
            statusMessage = configuration.mode == .plan
                ? VyronStatusText.planReadyReadOnly
                : VyronStatusText.replyReady(configuration.inferenceLocation)
        }
        finishConversationResponse(identity)
        guard isForeground else { return }
        requestSuggestedQuestions(using: inference.provider, request: .init(
            model: model, prompt: prompt, answer: answer, response: identity
        ))
    }

    private func chatResponseContext(
        for started: VyronStartedConversationResponse,
        skills: String?,
        project: String
    ) -> [String: String] {
        let reference = [skills, started.context.attachments.attachedContext, project.isEmpty ? nil : project]
            .compactMap { $0 }.joined(separator: VyronTextSeparator.paragraph.rawValue)
        var context = started.context.previousContext
        guard !reference.isEmpty else { return context }
        context[started.userMessageID.uuidString] = reference
        if let index = conversations.firstIndex(where: { $0.id == started.identity.conversationID }) {
            conversations[index].contextByMessageID = context
        }
        saveHistory()
        return context
    }
}
