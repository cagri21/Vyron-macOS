import Foundation
import VyronCore
import VyronDevelopment

extension AppModel {
    func makeMacWorkRun(
        context: VyronMacWorkContext, response: VyronResponseIdentity, allowsBackgroundChat: Bool = false
    ) -> VyronMacWorkRun {
        let session = VyronMacWorkSession(
            context: context,
            dependencies: VyronMacWorkDependencies(
                controller: computerWork.macWorkController,
                validateCurrent: { [weak self] in
                    guard let self, self.isCurrentMacWorkResponse(response, allowsBackgroundChat: allowsBackgroundChat)
                    else { throw CancellationError() }
                },
                review: { [weak self] request in
                    guard let self, self.isCurrentMacWorkResponse(response, allowsBackgroundChat: allowsBackgroundChat)
                    else { return false }
                    let ownedReview = MCPActionReview(
                        connectionName: request.connectionName, toolName: request.toolName, arguments: request.arguments,
                        responseOwner: VyronNotificationResponseID(
                            conversationID: response.conversationID, responseID: response.messageID
                        )
                    )
                    let approved = await self.mcpConnections.review(ownedReview)
                    return self.isCurrentMacWorkResponse(response, allowsBackgroundChat: allowsBackgroundChat)
                        && approved
                },
                onTargetAction: { [weak self] feedback in
                    self?.computerWork.macWorkOverlay.show(
                        title: feedback.title, targetFrame: feedback.targetFrame, owner: response.generationID
                    )
                }
            ),
            actions: computerWork.macActions
        )
        let screenshots = VyronMacWorkScreenshots(
            captureService: computerWork.macWorkScreenshotCapture,
            validateCurrent: { [weak self] in self?.isCurrentMacWorkResponse(response) == true },
            onCaptured: { [weak self] image in
                guard let self else { throw CancellationError() }
                try self.recordMacWorkScreenshot(image, response: response)
            }
        )
        return VyronMacWorkRun(session: session, screenshots: screenshots)
    }

    func isCurrentMacWorkResponse(_ response: VyronResponseIdentity, allowsBackgroundChat: Bool = false) -> Bool {
        guard !isRunningScheduledTask, !isShuttingDown, !Task.isCancelled else { return false }
        return ownsInteractiveWorkResponse(response) || (allowsBackgroundChat && foregroundRun.owns(response))
    }

    func recordMacWorkScreenshot(_ image: VyronImageAttachment, response: VyronResponseIdentity) throws {
        guard isCurrentMacWorkResponse(response),
            let conversationIndex = conversations.firstIndex(where: { $0.id == response.conversationID }),
            let messageIndex = conversations[conversationIndex].messages.firstIndex(where: {
                $0.id == response.messageID && $0.conversationRole == .assistant
            }) else { throw CancellationError() }
        try VyronImageAttachment.validate(messages: [ChatMessage(role: .user, content: "", images: [image])])
        var captures = conversations[conversationIndex].messages[messageIndex].capturedImages ?? []
        captures.append(image)
        while captures.count > VyronImageAttachment.maximumCount
            || captures.reduce(0, { $0 + $1.data.count }) > VyronImageAttachment.maximumRequestDataBytes {
            captures.removeFirst()
        }
        conversations[conversationIndex].messages[messageIndex].capturedImages = captures
        guard saveHistory() else {
            throw DevelopmentError("The screenshot was captured, but its conversation history could not be saved.")
        }
    }
}
