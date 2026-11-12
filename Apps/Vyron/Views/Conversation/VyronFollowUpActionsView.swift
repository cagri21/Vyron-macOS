import SwiftUI

struct VyronFollowUpActionsView: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let _ = localizationLocale
        HStack(spacing: VyronFollowUpStyle.controlSpacing) {
            if model.composer.isEditingQueuedMessage {
                Button(VyronScheduledTaskText.cancel) { model.composer.cancelQueuedMessageEdit() }
                    .font(VyronFollowUpStyle.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.muted)
                    .keyboardShortcut(.cancelAction)
            } else if model.foregroundRun.isGenerating {
                Menu {
                    Toggle(VyronQueueText.messages, isOn: Binding(
                        get: { model.composer.queueMessages },
                        set: { model.composer.queueMessages = $0 }
                    ))
                } label: {
                    Image(systemName: model.composer.queueMessages
                        ? VyronSymbols.messageQueue : VyronSymbols.messageSteer)
                        .font(VyronFollowUpStyle.icon)
                        .foregroundStyle(Palette.muted)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(VyronQueueText.followUpBehavior)
                .accessibilityLabel(VyronQueueText.followUpBehavior)
            }
            if model.foregroundRun.isGenerating || model.computerWork.isComputerWorkActive {
                Button { model.stopGeneration() } label: {
                    Image(systemName: VyronSymbols.stop)
                        .font(VyronFollowUpStyle.icon)
                        .frame(width: VyronFollowUpStyle.actionSize, height: VyronFollowUpStyle.actionSize)
                        .background(
                            Palette.field,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .help(VyronQueueText.stopTask)
                .accessibilityLabel(VyronQueueText.stopTask)
            }
            if !model.computerWork.isComputerWorkActive {
                Button { model.send() } label: {
                    Image(systemName: sendSymbol)
                        .font(VyronFollowUpStyle.sendIcon)
                        .foregroundStyle(model.canSend ? Palette.text : Palette.muted)
                        .frame(width: VyronFollowUpStyle.actionSize, height: VyronFollowUpStyle.actionSize)
                        .background(
                            model.canSend ? Palette.controlAccent : Palette.field,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!model.canSend)
                .keyboardShortcut(model.selectedUserInputRequest == nil
                    ? KeyboardShortcut(.return, modifiers: .command) : nil)
                .help(sendHelp)
                .accessibilityLabel(sendHelp)
            }
        }
    }

    private var sendSymbol: String {
        if model.composer.isEditingQueuedMessage { return VyronSymbols.check }
        if model.foregroundRun.isGenerating {
            return model.composer.queueMessages ? VyronSymbols.messageQueue : VyronSymbols.messageSteer
        }
        return VyronSymbols.send
    }

    private var sendHelp: String {
        if model.composer.isEditingQueuedMessage { return VyronQueueText.saveEdit }
        if model.foregroundRun.isGenerating {
            return model.composer.queueMessages ? VyronQueueText.message : VyronQueueText.steer
        }
        return VyronQueueText.runTask
    }
}
