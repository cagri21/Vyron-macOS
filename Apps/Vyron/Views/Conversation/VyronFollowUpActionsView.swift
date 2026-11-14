import SwiftUI

struct VyronFollowUpActionsView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    let submit: () -> Void

    var body: some View {
        let _ = localizationLocale
        let canSubmit = model.canSubmitComposer
        HStack(spacing: VyronFollowUpStyle.controlSpacing) {
            if model.composer.isEditingQueuedMessage {
                Button(VyronScheduledTaskText.cancel) { model.composer.cancelQueuedMessageEdit() }
                    .font(VyronFollowUpStyle.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.muted)
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
                        .foregroundStyle(palette.muted)
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
                            palette.field,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .help(VyronQueueText.stopTask)
                .accessibilityLabel(VyronQueueText.stopTask)
            }
            if !model.computerWork.isComputerWorkActive {
                Button(action: submit) {
                    Image(systemName: sendSymbol)
                        .font(VyronFollowUpStyle.sendIcon)
                        .foregroundStyle(canSubmit ? palette.onControlAccent : palette.muted)
                        .frame(width: VyronFollowUpStyle.actionSize, height: VyronFollowUpStyle.actionSize)
                        .background(
                            canSubmit ? palette.controlAccent : palette.field,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .keyboardShortcut(model.selectedUserInputRequest == nil
                    ? KeyboardShortcut(.return, modifiers: .command) : nil)
                .help(sendHelp)
                .accessibilityLabel(sendHelp)
            }
        }
    }

    private var sendSymbol: String {
        if model.composer.isEditingQueuedMessage { return VyronSymbols.check }
        if model.sideChatCommand != nil { return VyronSymbols.sideChat }
        if model.foregroundRun.isGenerating {
            return model.composer.queueMessages ? VyronSymbols.messageQueue : VyronSymbols.messageSteer
        }
        return VyronSymbols.send
    }

    private var sendHelp: String {
        if model.composer.isEditingQueuedMessage { return VyronQueueText.saveEdit }
        if model.sideChatCommand != nil { return VyronToolsText.sideChat }
        if model.foregroundRun.isGenerating {
            return model.composer.queueMessages ? VyronQueueText.message : VyronQueueText.steer
        }
        return VyronQueueText.runTask
    }
}
