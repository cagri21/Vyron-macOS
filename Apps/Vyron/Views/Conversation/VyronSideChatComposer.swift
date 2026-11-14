import AppKit
import SwiftUI

struct VyronSideChatComposer: View {
    @Environment(\.vyronPalette) private var palette
    @EnvironmentObject private var model: AppModel
    @ObservedObject var session: VyronSideChatSession
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: VyronConversationWindowStyle.composerSpacing) {
            if let error = session.errorMessage {
                Text(verbatim: error)
                    .font(VyronConversationWindowStyle.detail)
                    .foregroundStyle(palette.warning)
                    .textSelection(.enabled)
                if let answer = session.unsavedAnswer {
                    Button(VyronGeneralText.copyResponse) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(answer, forType: .string)
                    }
                    .font(VyronConversationWindowStyle.action)
                    .buttonStyle(QuietButtonStyle(foreground: palette.text))
                }
            }
            HStack(alignment: .bottom, spacing: VyronConversationWindowStyle.composerSpacing) {
                TextField(VyronWorkspaceText.placeholderChat, text: $session.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(VyronWorkspaceStyle.inputFont)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .disabled(model.isShuttingDown)
                    .accessibilityLabel(VyronWorkspaceText.placeholderChat)
                    .accessibilityHint(VyronWorkspaceText.composerKeyboardHint)
                    .onAppear {
                        if model.isTemporarySideChat(session.context.conversationID) { inputFocused = true }
                    }
                    .onKeyPress(.return, phases: .down) { keyPress in
                        guard inputFocused, !model.isShuttingDown else { return .ignored }
                        return VyronComposerReturnKey.handle(
                            modifiers: keyPress.modifiers,
                            editor: NSApp.keyWindow?.firstResponder as? NSTextInputClient
                        ) {
                            session.send()
                        }
                    }
                if session.isGenerating {
                    Button { session.stop() } label: {
                        Image(systemName: VyronSymbols.stop)
                            .frame(
                                width: VyronConversationWindowStyle.actionSize,
                                height: VyronConversationWindowStyle.actionSize
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.text)
                    .help(VyronWorkspaceText.stopTask)
                    .accessibilityLabel(VyronWorkspaceText.stopTask)
                } else {
                    Button { session.send() } label: {
                        Image(systemName: VyronSymbols.send)
                            .frame(
                                width: VyronConversationWindowStyle.actionSize,
                                height: VyronConversationWindowStyle.actionSize
                            )
                            .background(palette.controlAccent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.text)
                    .disabled(!session.canSend)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help(VyronQueueText.sendNow)
                    .accessibilityLabel(VyronQueueText.sendNow)
                }
            }
            .padding(VyronConversationWindowStyle.headerInset)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: VyronConversationWindowStyle.composerRadius))
            Text(verbatim: "\(session.configuration.connection.name) · \(session.configuration.model)")
                .font(VyronConversationWindowStyle.detail)
                .foregroundStyle(palette.muted)
        }
    }
}
