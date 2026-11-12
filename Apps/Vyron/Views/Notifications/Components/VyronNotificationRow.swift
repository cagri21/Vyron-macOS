import SwiftUI

struct VyronNotificationRow: View {
    @Environment(\.locale) private var localizationLocale
    @Environment(\.calendar) private var calendar
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    let item: VyronNotificationItem
    let relativeTo: Date
    @State private var openingBlocked = false

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronNotificationStyle.contentSpacing) {
            Button(action: open) {
                content
                    .padding(.horizontal, VyronNotificationStyle.rowHorizontalInset)
                    .padding(.vertical, VyronNotificationStyle.rowVerticalInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(VyronSidebarRowBackground(isSelected: isSelected))
            .help(item.content.title + "\n" + item.content.preview)
            .accessibilityElement(children: .combine)
            .accessibilityValue(item.isUnread ? VyronNotificationText.unreadCount(1) : "")
            .accessibilityHint(VyronNotificationText.open)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .contextMenu {
                Button(VyronNotificationText.open, action: open)
                Button(VyronNotificationText.openInWindow, action: openInWindow)
                    .disabled(item.conversationID == nil)
                Divider()
                Button(VyronNotificationText.markRead) { model.markNotificationRead(item.id) }
                    .disabled(!item.isUnread || !model.notifications.storageWritable)
            }
            if openingBlocked {
                Text(item.id.target == .plugins && model.voice.isActive
                    ? VyronNotificationText.voiceBusy : VyronNotificationText.openBlocked)
                    .font(VyronNotificationStyle.preview)
                    .foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, VyronNotificationStyle.rowHorizontalInset)
                    .padding(.bottom, VyronNotificationStyle.rowVerticalInset)
            }
        }
        .onChange(of: item.id) { _, _ in openingBlocked = false }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: VyronNotificationStyle.contentSpacing) {
            HStack(spacing: VyronNotificationStyle.titleSpacing) {
                Text(verbatim: item.content.title)
                    .font(item.isUnread ? VyronNotificationStyle.unreadTitle : VyronNotificationStyle.title)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let projectName {
                    Text(verbatim: projectName)
                        .font(VyronNotificationStyle.title)
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .frame(maxWidth: VyronNotificationStyle.projectMaximumWidth, alignment: .leading)
                }
                Spacer(minLength: 0)
                indicator
            }
            if !item.content.preview.isEmpty {
                Text(verbatim: item.content.preview)
                    .font(VyronNotificationStyle.preview)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: VyronNotificationStyle.statusSpacing) {
                Label(
                    VyronNotificationPresentation.title(item.kind),
                    systemImage: VyronNotificationPresentation.symbol(item.kind)
                )
                .font(VyronNotificationStyle.status)
                .foregroundStyle(VyronNotificationPresentation.color(item.kind))
                Spacer(minLength: 0)
                if calendar.isDate(item.date, inSameDayAs: relativeTo) {
                    Text(item.date, style: .time)
                } else {
                    Text(item.date, style: .date)
                }
            }
            .font(VyronNotificationStyle.detail)
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private var indicator: some View {
        if item.isLive {
            ProgressView().controlSize(.mini)
                .frame(width: VyronNotificationStyle.indicatorSize, height: VyronNotificationStyle.indicatorSize)
                .accessibilityHidden(true)
        } else if item.isUnread {
            Circle().fill(Palette.controlAccent)
                .frame(width: VyronNotificationStyle.rowUnreadSize, height: VyronNotificationStyle.rowUnreadSize)
                .frame(width: VyronNotificationStyle.indicatorSize, height: VyronNotificationStyle.indicatorSize)
                .accessibilityHidden(true)
        }
    }

    private var projectName: String? {
        item.content.projectPath.map { model.sidebarProjectName($0) }
    }

    private var isSelected: Bool {
        guard let conversationID = item.conversationID, model.selectedConversationID == conversationID else {
            return false
        }
        if let selection = model.appNavigation.trackingSelection, selection.conversationID == conversationID {
            return selection.messageID == item.responseID
        }
        return model.messages.last(where: { $0.conversationRole == .assistant })?.id == item.responseID
    }

    private func open() {
        openingBlocked = false
        if model.openNotification(item) { return }
        openInWindow()
    }

    private func openInWindow() {
        guard let conversationID = model.notificationWindowTarget(item) else {
            openingBlocked = true
            return
        }
        openingBlocked = false
        openWindow(id: VyronAppWindow.conversation, value: conversationID)
    }
}
