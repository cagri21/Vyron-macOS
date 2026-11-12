import Foundation
import VyronCore

extension AppModel {
    static func validateSkillContext(_ context: String?, prompt: String, images: [VyronImageAttachment]) throws {
        guard let context else { return }
        let size = context.utf8.count + prompt.utf8.count + VyronConversationRequestContext.systemPrompt.utf8.count
            + VyronConversationLimits.skillContextOverheadBytes
            + images.count * VyronImageAttachment.estimatedContextTokens
        guard size <= VyronScreenshotLimits.maximumConversationBudget else {
            throw VyronSkillContextError.tooLarge
        }
    }
}
