import SwiftUI

struct VyronNotificationsView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let _ = localizationLocale
        TimelineView(.periodic(from: .now, by: VyronNotificationStyle.refreshInterval)) { context in
            let groups = model.notificationGroups
            VStack(alignment: .leading, spacing: 0) {
                header
                if let error = model.notifications.storageError {
                    storageError(error)
                }
                if groups.isEmpty {
                    emptyState
                } else {
                    feed(groups, relativeTo: context.date)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(spacing: VyronNotificationStyle.headerSpacing) {
            Text(VyronNotificationText.title).font(VyronNotificationStyle.heading)
            Spacer(minLength: 0)
            Button { model.markAllNotificationsRead() } label: {
                Image(systemName: VyronSymbols.checkCircle)
                    .font(VyronNotificationStyle.bell)
            }
            .buttonStyle(.plain)
            .disabled(!canMarkAllRead)
            .foregroundStyle(canMarkAllRead ? palette.text : palette.muted)
            .help(VyronNotificationText.markAllRead)
            .accessibilityLabel(VyronNotificationText.markAllRead)
        }
        .foregroundStyle(palette.text)
        .padding(.horizontal, VyronNotificationStyle.headerInset)
        .padding(.vertical, VyronNotificationStyle.headerVerticalInset)
    }

    private var canMarkAllRead: Bool {
        model.notifications.storageWritable && model.unreadNotificationCount > 0
    }

    private func storageError(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: VyronNotificationStyle.headerSpacing) {
            Label { Text(verbatim: error) } icon: { Image(systemName: VyronSymbols.warning) }
                .font(VyronNotificationStyle.preview)
                .foregroundStyle(palette.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            Button { model.reloadNotificationReadState() } label: {
                Label(VyronNotificationText.retry, systemImage: VyronSymbols.refresh)
                    .font(VyronNotificationStyle.action)
                    .foregroundStyle(palette.text)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(VyronNotificationText.retry)
        }
        .padding(VyronNotificationStyle.storageErrorInset)
    }

    private var emptyState: some View {
        VStack(spacing: VyronNotificationStyle.emptySpacing) {
            Image(systemName: VyronSymbols.notifications)
                .font(VyronNotificationStyle.emptySymbol)
                .accessibilityHidden(true)
            Text(VyronNotificationText.emptyTitle)
                .font(VyronNotificationStyle.heading)
            Text(VyronNotificationText.emptyDetail)
                .font(VyronNotificationStyle.preview)
        }
        .foregroundStyle(palette.muted)
        .multilineTextAlignment(.center)
        .padding(VyronNotificationStyle.emptyInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func feed(_ groups: [VyronNotificationGroup], relativeTo date: Date) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VyronNotificationStyle.sectionSpacing) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: VyronNotificationStyle.rowSpacing) {
                        Text(VyronNotificationPresentation.title(group.id))
                            .font(VyronNotificationStyle.section)
                            .foregroundStyle(palette.muted)
                            .padding(.horizontal, VyronNotificationStyle.sectionHeaderInset)
                            .padding(.bottom, VyronNotificationStyle.sectionHeaderBottomInset)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.items) { item in
                            VyronNotificationRow(item: item, relativeTo: date)
                        }
                    }
                }
            }
            .padding(.horizontal, VyronNotificationStyle.listInset)
            .padding(.bottom, VyronNotificationStyle.sectionSpacing)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel(VyronNotificationText.allNotifications)
    }
}
