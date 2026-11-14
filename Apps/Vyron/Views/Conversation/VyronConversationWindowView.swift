import SwiftUI
import VyronCore

struct VyronConversationWindowView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    let conversationID: UUID

    private var conversation: Conversation? { model.sideChatConversation(with: conversationID) }
    private var session: VyronSideChatSession? { model.newSideChatSessions[conversationID] }
    private var isTemporary: Bool { model.isTemporarySideChat(conversationID) }

    var body: some View {
        let _ = localizationLocale
        VStack(spacing: 0) {
            header
            Rectangle().fill(palette.border).frame(height: VyronWorkspaceStyle.dividerWidth)
            if let conversation {
                transcript(conversation)
                if let session {
                    VyronSideChatComposer(session: session)
                        .padding(VyronConversationWindowStyle.contentInset)
                } else {
                    Text(VyronHeaderText.readOnlyWindow)
                        .font(VyronConversationWindowStyle.detail)
                        .foregroundStyle(palette.muted)
                        .padding(VyronConversationWindowStyle.contentInset)
                }
            } else {
                Text(VyronHeaderText.conversationUnavailable)
                    .font(VyronConversationWindowStyle.detail)
                    .foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(palette.canvas)
        .foregroundStyle(palette.text)
        .tint(palette.text)
        .navigationTitle(conversation?.title ?? "Vyron")
        .onDisappear { model.closeSideChatWindow(conversationID) }
    }

    private var header: some View {
        HStack(spacing: VyronConversationWindowStyle.composerSpacing) {
            VStack(alignment: .leading, spacing: VyronWorkspaceStyle.compactSpacing) {
                Text(verbatim: conversation?.title ?? "Vyron")
                    .font(VyronConversationWindowStyle.title)
                    .lineLimit(1)
                if let session {
                    Text(isTemporary
                        ? VyronHeaderText.temporarySideChatContext(session.context.sourceTitle)
                        : VyronHeaderText.sideChatContext(session.context.sourceTitle))
                        .font(VyronConversationWindowStyle.detail)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if !isTemporary {
                Button {
                    if model.openSideChatInMain(conversationID) { openWindow(id: VyronAppWindow.main) }
                } label: {
                    Label(VyronHeaderText.openInMain, systemImage: VyronSymbols.openWindow)
                        .font(VyronConversationWindowStyle.action)
                }
                .buttonStyle(QuietButtonStyle(foreground: palette.text))
                .disabled(!model.canOpenSideChatInMain(conversationID))
            }
        }
        .padding(VyronConversationWindowStyle.headerInset)
    }

    private func transcript(_ conversation: Conversation) -> some View {
        let transcript = VyronConversationTranscript(messages: conversation.messages)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: VyronConversationWindowStyle.messageSpacing) {
                    ForEach(transcript.rows) { row in
                        let message = row.message
                        VyronConversationWindowMessageView(
                            message: message,
                            isStreaming: model.isResponseActivityLive(
                                conversationID: conversationID, messageID: message.id
                            ),
                            clarificationAnswers: row.clarificationAnswers
                        )
                        .id(message.id)
                    }
                }
                .frame(maxWidth: VyronWorkspaceStyle.contentWidth)
                .padding(VyronConversationWindowStyle.contentInset)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: conversation.messages.last?.content) { _, _ in
                if let id = conversation.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }
}
