import AppKit
import SwiftUI
import VyronCore

struct VyronConversationMessageView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    let message: ChatMessage
    let isStreaming: Bool
    var showsResponseChanges = false
    var clarificationAnswers: [VyronClarificationAnswer] = []
    @State private var copied = false
    private var isUser: Bool { message.conversationRole == .user }
    private var displayContent: String {
        guard !isUser else { return message.content }
        var inCode = false
        var fence = "```"
        return message.content.components(separatedBy: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inCode, trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inCode = true
                fence = String(trimmed.prefix(3))
                return line
            }
            if inCode, trimmed.hasPrefix(fence) {
                inCode = false
                return line
            }
            guard !inCode else { return line }
            var cleaned = line
            while let range = cleaned.range(of: #"</?tool_call>\s*$"#, options: .regularExpression) {
                let prefix = String(cleaned[..<range.lowerBound])
                guard prefix.filter({ $0 == "`" }).count.isMultiple(of: 2) else { break }
                cleaned = prefix
            }
            return cleaned.trimmingCharacters(in: .whitespaces).isEmpty && !trimmed.isEmpty ? nil : cleaned
        }.joined(separator: "\n")
    }

    var body: some View {
        let _ = localizationLocale
        Group {
            if isUser {
                userMessage
            } else {
                assistantMessage
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isUser ? VyronGeneralText.you : "Vyron")
    }

    private var userMessage: some View {
        HStack {
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: VyronWorkspaceStyle.controlSpacing) {
                userAttachments
                if let filename = message.developmentTaskFilename {
                    VyronDevelopmentTaskAttachmentView(filename: filename, content: message.content)
                } else {
                    VyronUserMessageBubble(content: message.content, clarificationAnswers: clarificationAnswers)
                        .frame(maxWidth: VyronConversationStyle.maximumUserWidth, alignment: .trailing)
                }
            }
            .frame(maxWidth: VyronConversationStyle.maximumUserWidth, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var userAttachments: some View {
        let pdfs = message.pdfPreviews ?? []
        let files = message.fileAttachments ?? []
        let applications = message.applicationAttachments ?? []
        if !pdfs.isEmpty || !files.isEmpty || !applications.isEmpty {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: VyronWorkspaceStyle.controlSpacing) {
                    ForEach(message.images ?? []) { image in
                        VyronScreenshotAttachmentCard(attachment: image)
                    }
                    ForEach(pdfs) { pdf in
                        VyronPDFAttachmentCard(attachment: pdf)
                    }
                    ForEach(files) { file in
                        VyronFileAttachmentCard(info: file)
                    }
                    ForEach(applications) { application in
                        VyronApplicationAttachmentCard(attachment: application, remove: nil)
                    }
                }
            }
        } else if let images = message.images, !images.isEmpty {
            VyronScreenshotAttachmentsView(images: images)
        }
    }

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: VyronConversationStyle.contentSpacing) {
            if let activity = message.activity {
                VyronResponseActivityView(
                    activity: activity,
                    response: message.content,
                    isStreaming: isStreaming,
                    messageID: message.id
                )
            }
            if message.content.isEmpty, isStreaming, message.activity == nil {
                HStack(spacing: VyronConversationStyle.rowSpacing) {
                    ProgressView().controlSize(.mini)
                    Text(VyronGeneralText.loadingContext)
                        .font(VyronConversationStyle.activity)
                        .foregroundStyle(palette.muted)
                }
            } else if !displayContent.isEmpty {
                MarkdownContent(content: displayContent)
            }
            if let images = message.capturedImages, !images.isEmpty {
                VyronScreenshotAttachmentsView(images: images)
            }
            if showsResponseChanges, !isStreaming {
                VyronResponseChangesView(responseID: message.id)
            }
            if !isStreaming, !displayContent.isEmpty {
                copyButton
            }
        }
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(displayContent, forType: .string)
            copied = true
        } label: {
            Image(systemName: copied ? VyronSymbols.checkmark : VyronSymbols.copy)
                .font(VyronConversationStyle.icon)
                .foregroundStyle(copied ? palette.success : palette.muted)
                .padding(.top, VyronConversationStyle.copyTopPadding)
        }
        .buttonStyle(.plain)
        .help(copied ? VyronGeneralText.copied : VyronGeneralText.copyResponse)
        .accessibilityLabel(copied ? VyronGeneralText.copied : VyronGeneralText.copyResponse)
        .task(id: copied) {
            guard copied else { return }
            do {
                try await Task.sleep(for: VyronConversationStyle.copyFeedbackDuration)
            } catch {
                return
            }
            copied = false
        }
    }
}
