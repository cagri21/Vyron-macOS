import SwiftUI
import VyronCore

struct VyronActivityTrailView: View {
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    let activity: ResponseActivity
    let summary: String?
    let selectedEntryID: UUID?
    let revealID: UUID?
    @State private var expandedEntries = Set<UUID>()

    init(
        activity: ResponseActivity,
        summary: String? = nil,
        selectedEntryID: UUID? = nil,
        revealID: UUID? = nil
    ) {
        self.activity = activity
        self.summary = summary
        self.selectedEntryID = selectedEntryID
        self.revealID = revealID
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: VyronTrackingStyle.compactSpacing) {
            ForEach(visibleEntries) { entry in
                VStack(alignment: .leading, spacing: VyronTrackingStyle.compactSpacing) {
                    Text(VyronTaskDatePresentation.eventTime(for: entry.date, locale: locale, timeZone: timeZone))
                        .font(VyronTrackingStyle.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                    if entry.kind == .explanation {
                        MarkdownContent(content: entry.detail ?? entry.title)
                            .padding(.vertical, VyronTrackingStyle.rowVerticalPadding)
                    } else {
                        activityRow(entry)
                    }
                }
                .id(entry.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: revealID, initial: true) { _, _ in
            if let selectedEntryID { expandedEntries.insert(selectedEntryID) }
        }
    }

    private var visibleEntries: [ResponseActivity.Entry] {
        guard activity.state == .completed,
            let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines),
            let explanation = activity.entries.last(where: { $0.kind == .explanation }),
            let detail = explanation.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
            !detail.isEmpty, summary.hasPrefix(detail)
        else { return activity.entries }
        return activity.entries.filter { $0.id != explanation.id }
    }

    private func activityRow(_ entry: ResponseActivity.Entry) -> some View {
        HStack(alignment: .top, spacing: VyronTrackingStyle.rowSpacing) {
            Image(systemName: VyronTrackingPresentation.symbol(entry))
                .font(VyronTrackingStyle.icon)
                .frame(width: VyronTrackingStyle.iconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: VyronTrackingStyle.compactSpacing) {
                if let detail = entry.detail, !detail.isEmpty {
                    DisclosureGroup(isExpanded: Binding(
                        get: { expandedEntries.contains(entry.id) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedEntries.insert(entry.id)
                            } else {
                                expandedEntries.remove(entry.id)
                            }
                        }
                    )) {
                        Text(verbatim: detail)
                            .font(VyronTrackingStyle.detail)
                            .textSelection(.enabled)
                            .padding(.vertical, VyronTrackingStyle.rowVerticalPadding)
                    } label: {
                        Text(verbatim: entry.title)
                            .font(VyronTrackingStyle.activity)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(verbatim: entry.title)
                        .font(VyronTrackingStyle.activity)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(Palette.muted)
        .padding(.vertical, VyronTrackingStyle.rowVerticalPadding)
    }
}
