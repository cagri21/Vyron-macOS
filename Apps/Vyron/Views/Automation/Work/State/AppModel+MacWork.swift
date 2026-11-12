import Foundation
import VyronCore
import VyronDevelopment

extension AppModel {
    func makeMacWorkRun(context: VyronMacWorkContext, response: VyronResponseIdentity) -> VyronMacWorkRun {
        let session = VyronMacWorkSession(
            context: context,
            dependencies: VyronMacWorkDependencies(
                controller: computerWork.macWorkController,
                validateCurrent: { [weak self] in
                    guard let self, self.isCurrentMacWorkResponse(response) else { throw CancellationError() }
                },
                review: { [weak self] request in
                    guard let self, self.isCurrentMacWorkResponse(response) else { return false }
                    let approved = await self.mcpConnections.review(request)
                    return self.isCurrentMacWorkResponse(response) && approved
                },
                onTargetAction: { [weak self] feedback in
                    self?.computerWork.macWorkOverlay.show(
                        title: feedback.title, targetFrame: feedback.targetFrame, owner: response.generationID
                    )
                }
            )
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

    func isCurrentMacWorkResponse(_ response: VyronResponseIdentity) -> Bool {
        !isRunningScheduledTask && ownsInteractiveWorkResponse(response)
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
