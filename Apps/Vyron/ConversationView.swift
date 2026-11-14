import AppKit
import SwiftUI
import VyronCore

struct ConversationView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let taskDates = VyronConversationTimeline(messages: model.messages).startDatesByMessageID
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: VyronConversationStyle.turnSpacing) {
                    ForEach(model.messages) { message in
                        VStack(alignment: .leading, spacing: VyronConversationStyle.rowSpacing) {
                            if let date = taskDates[message.id] {
                                VyronConversationTaskTimestamp(date: date)
                            }
                            VyronConversationMessageView(
                                message: message,
                                isStreaming: model.isResponseActivityLive(messageID: message.id),
                                showsResponseChanges: true
                            )
                        }
                        .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("conversation-bottom")
                }
                .frame(maxWidth: VyronWorkspaceStyle.contentWidth, alignment: .leading)
                .padding(.horizontal, VyronWorkspaceStyle.outerPadding)
                .padding(.top, 33)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.messages.last?.content) { _, _ in
                if isLatestResponseLive { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
            }
            .onChange(of: model.messages.last?.activity?.entries.last?.id) { _, _ in
                if isLatestResponseLive { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
            }
            .onChange(of: model.selectedConversationID) { _, _ in
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
            .onAppear { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
        }
    }

    private var isLatestResponseLive: Bool {
        guard let messageID = model.messages.last?.id else { return false }
        return model.isResponseActivityLive(messageID: messageID)
    }
}

private struct MarkdownSegment: Identifiable {
    let id: Int
    let content: String
    let language: String?
    let isCode: Bool
}

struct MarkdownContent: View {
    @Environment(\.locale) private var localizationLocale
    let content: String

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: 15) {
            ForEach(segments) { segment in
                if segment.isCode {
                    CodeBlock(code: segment.content, language: segment.language ?? VyronGeneralText.code)
                } else {
                    MarkdownProse(content: segment.content)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var segments: [MarkdownSegment] {
        var output: [MarkdownSegment] = []
        var lines: [String] = []
        var inCode = false
        var language: String?
        var fence = "```"
        func flush() {
            let text = lines.joined(separator: "\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output.append(MarkdownSegment(id: output.count, content: text, language: language, isCode: inCode))
            }
            lines = []
        }
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if (!inCode && (trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")))
                || (inCode && trimmed.hasPrefix(fence)) {
                flush()
                if inCode {
                    inCode = false
                    language = nil
                } else {
                    inCode = true
                    fence = String(trimmed.prefix(3))
                    let identifier = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    language = identifier.isEmpty ? nil : identifier
                }
            } else {
                lines.append(line)
            }
        }
        flush()
        return output
    }
}

private struct MarkdownProse: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(content.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    Color.clear.frame(height: 3)
                } else if trimmed.hasPrefix("### ") {
                    prose(String(trimmed.dropFirst(4))).font(.system(size: 13, weight: .semibold)).padding(.top, 5)
                } else if trimmed.hasPrefix("## ") {
                    prose(String(trimmed.dropFirst(3))).font(.system(size: 15, weight: .semibold)).padding(.top, 7)
                } else if trimmed.hasPrefix("# ") {
                    prose(String(trimmed.dropFirst(2))).font(.system(size: 17, weight: .semibold)).padding(.top, 7)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    HStack(alignment: .top, spacing: 9) {
                        Text("•").foregroundStyle(Palette.accent.opacity(0.7))
                        prose(String(trimmed.dropFirst(2)))
                    }
                } else if trimmed.hasPrefix("> ") {
                    HStack(alignment: .top, spacing: 11) {
                        RoundedRectangle(cornerRadius: 1).fill(Palette.accent.opacity(0.4)).frame(width: 2)
                        prose(String(trimmed.dropFirst(2))).foregroundStyle(Palette.muted)
                    }
                    .padding(.vertical, 5)
                } else {
                    prose(line)
                }
            }
        }
        .font(VyronConversationStyle.prose)
        .lineSpacing(VyronConversationStyle.proseLineSpacing)
        .foregroundStyle(Palette.text.opacity(0.92))
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func prose(_ line: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: line,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(line)
    }
}

private struct CodeBlock: View {
    @Environment(\.locale) private var localizationLocale
    let code: String
    let language: String
    @State private var copied = false

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.uppercased())
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5)); copied = false
                    }
                } label: {
                    Label(
                        copied ? VyronGeneralText.copied : VyronGeneralText.copy,
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                        .font(.system(size: 9))
                        .foregroundStyle(copied ? Palette.success : Palette.muted)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Palette.raised.opacity(0.4))
            Rectangle().fill(Palette.border).frame(height: 1)
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .lineSpacing(5)
                    .foregroundStyle(Palette.codeText.opacity(0.9))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(15)
            }
        }
        .background(Palette.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.border))
    }
}
