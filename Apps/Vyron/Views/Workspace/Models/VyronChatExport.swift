import Foundation
import VyronCore

/// Only the visible transcript is exported. Internal context, tool activity and image bytes stay private.
struct VyronChatExport {
    let title: String
    let markdown: String
    let plainText: String

    var text: String { markdown }

    init(conversation: Conversation) {
        title = conversation.title
        var markdownParts = ["# " + Self.singleLine(conversation.title)]
        var plainParts = [Self.singleLine(conversation.title)]
        for message in conversation.messages {
            let role: String
            switch message.conversationRole {
            case .user: role = VyronHeaderText.exportUser
            case .assistant: role = VyronHeaderText.exportAssistant
            case nil: continue
            }
            let attachments = (message.images ?? []).map { Self.singleLine($0.name) }
            guard !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !attachments.isEmpty else { continue }
            var markdownMessage = "## " + role
            var plainMessage = role + ":"
            if !message.content.isEmpty {
                markdownMessage += "\n\n" + message.content
                plainMessage += "\n" + message.content
            }
            if !attachments.isEmpty {
                let names = attachments.map { "- " + $0 }.joined(separator: "\n")
                markdownMessage += "\n\n" + VyronHeaderText.exportAttachments + ":\n" + names
                plainMessage += "\n\n" + VyronHeaderText.exportAttachments + ":\n" + names
            }
            markdownParts.append(markdownMessage)
            plainParts.append(plainMessage)
        }
        markdown = markdownParts.joined(separator: "\n\n")
        plainText = plainParts.joined(separator: "\n\n")
    }

    private static func singleLine(_ value: String) -> String {
        value.components(separatedBy: .controlCharacters).joined(separator: " ")
    }
}
