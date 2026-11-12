import SwiftUI

struct VyronQueuedMessageRow: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @State private var isDropTarget = false
    let message: VyronQueuedMessage
    private var isPending: Bool { model.composer.pendingSteeringIDs.contains(message.id) }

    var body: some View {
        let _ = localizationLocale
        HStack(alignment: .firstTextBaseline, spacing: VyronFollowUpStyle.controlSpacing) {
            draggableMessage
            Button {
                model.steerQueuedMessage(message.id)
            } label: {
                HStack(spacing: VyronFollowUpStyle.rowSpacing) {
                    if isPending {
                        ProgressView().controlSize(.mini).accessibilityHidden(true)
                        Text(VyronQueueText.applying)
                    } else {
                        Label(
                            model.foregroundRun.isGenerating ? VyronQueueText.steer : VyronQueueText.sendNow,
                            systemImage: VyronSymbols.messageSteer
                        )
                    }
                }
                .font(VyronFollowUpStyle.caption).fixedSize()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.muted)
            .disabled(isPending || !model.canSteerQueuedMessage(message))
            .help(isPending ? VyronQueueText.updatePending : steerHelp)
            Button {
                model.deleteQueuedMessage(message.id)
            } label: {
                Image(systemName: VyronSymbols.trash)
                    .font(VyronFollowUpStyle.icon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.muted)
            .disabled(isPending)
            .help(VyronQueueText.deleteMessage)
            .accessibilityLabel(VyronQueueText.deleteMessage)
            Menu {
                Button {
                    model.editQueuedMessage(message.id)
                } label: {
                    Label(VyronQueueText.editMessage, systemImage: VyronSymbols.pencil)
                }
                .disabled(isPending || model.composer.isEditingQueuedMessage)
                Button(VyronQueueText.moveUp) { moveMessage(offset: -1) }
                    .disabled(!canMove(offset: -1))
                Button(VyronQueueText.moveDown) { moveMessage(offset: 1) }
                    .disabled(!canMove(offset: 1))
                Divider()
                Button {
                    model.composer.queueMessages.toggle()
                } label: {
                    Label(
                        model.composer.queueMessages
                            ? VyronQueueText.turnOff : VyronQueueText.turnOn,
                        systemImage: VyronSymbols.messageQueue
                    )
                }
            } label: {
                Image(systemName: VyronSymbols.ellipsis)
                    .font(VyronFollowUpStyle.icon)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(VyronQueueText.messageOptions)
            .accessibilityLabel(VyronQueueText.messageOptions)
        }
        .padding(.horizontal, VyronFollowUpStyle.horizontalPadding)
        .padding(.vertical, VyronFollowUpStyle.verticalPadding)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: VyronFollowUpStyle.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: VyronFollowUpStyle.cornerRadius).stroke(
            isDropTarget && model.canReorderQueuedMessage(message.id) ? Palette.accent : Palette.border
        ))
        .dropDestination(for: VyronQueuedMessageDrag.self) { items, _ in
            guard items.count == 1, let item = items.first else { return false }
            return model.moveQueuedMessage(item.messageID, to: message.id, conversationID: item.conversationID)
        } isTargeted: { isDropTarget = $0 }
    }

    @ViewBuilder
    private var draggableMessage: some View {
        if model.canReorderQueuedMessage(message.id), let conversationID = model.selectedConversationID {
            messageLabel
                .draggable(VyronQueuedMessageDrag(conversationID: conversationID, messageID: message.id))
                .help(VyronQueueText.reorderHint)
                .accessibilityHint(VyronQueueText.reorderHint)
        } else {
            messageLabel
        }
    }

    private var messageLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: VyronFollowUpStyle.controlSpacing) {
            Image(systemName: VyronSymbols.messageQueue)
                .font(VyronFollowUpStyle.icon)
                .foregroundStyle(Palette.muted)
                .accessibilityHidden(true)
            Text(verbatim: message.content)
                .font(VyronFollowUpStyle.body)
                .foregroundStyle(Palette.text)
                .lineLimit(2)
                .help(message.content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private func moveTarget(offset: Int) -> UUID? {
        let messages = model.queuedMessages
        guard let index = messages.firstIndex(where: { $0.id == message.id }),
            messages.indices.contains(index + offset)
        else { return nil }
        return messages[index + offset].id
    }

    private func canMove(offset: Int) -> Bool {
        guard let targetID = moveTarget(offset: offset) else { return false }
        return model.canReorderQueuedMessage(message.id) && model.canReorderQueuedMessage(targetID)
    }

    private func moveMessage(offset: Int) {
        guard let targetID = moveTarget(offset: offset), let conversationID = model.selectedConversationID else { return }
        model.moveQueuedMessage(message.id, to: targetID, conversationID: conversationID)
    }

    private var steerHelp: String {
        if model.foregroundRun.isGenerating, VyronConversationCompactionCommand(prompt: message.content) != nil {
            return VyronCompactionText.wait
        }
        return model.foregroundRun.isGenerating ? VyronQueueText.steerHelp : VyronQueueText.sendNow
    }
}
