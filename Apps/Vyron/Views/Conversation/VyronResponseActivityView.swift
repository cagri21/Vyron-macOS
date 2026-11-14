import SwiftUI
import VyronCore

struct VyronResponseActivityView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    let activity: ResponseActivity
    let response: String
    let isStreaming: Bool
    let messageID: UUID
    @State private var isTimelineExpanded = false

    private var presentation: VyronActivityPresentation {
        VyronActivityPresentation(activity: activity, response: response, isStreaming: isStreaming)
    }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronConversationStyle.contentSpacing) {
            elapsedSummary
            if isTimelineExpanded {
                VyronActivityTrailView(activity: activity, summary: response)
            } else if isStreaming && activity.state == .working {
                ForEach(presentation.blocks) { block in
                    switch block {
                    case .explanation(let explanation):
                        MarkdownContent(content: explanation.text)
                    case .tools(let group):
                        VyronActivityToolsView(
                            group: group,
                            isCurrent: group.entries.last?.id == activity.entries.last?.id,
                            onInspect: { openTracking(entryID: $0) }
                        )
                    }
                }
            }
            if !activity.subagentActivities.isEmpty && (isTimelineExpanded || isStreaming) {
                VyronSubagentsLaunchView(messageID: messageID, subagents: activity.subagentActivities)
            }
            if isStreaming, activity.state == .working {
                Button { openTracking() } label: {
                    Text(tracking.inlinePhase)
                        .font(VyronConversationStyle.activity)
                        .foregroundStyle(palette.muted)
                        .modifier(VyronActivityShimmerModifier(isActive: true))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(VyronTrackingText.viewActivity)
            } else if let status = presentation.currentStatus {
                statusRow(status)
            }
            if presentation.showsDetailsLink {
                Button(VyronTrackingText.viewActivity) { openTracking() }
                    .font(VyronConversationStyle.activity)
                    .foregroundStyle(palette.accent)
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var elapsedSummary: some View {
        VStack(alignment: .leading, spacing: VyronWorkspaceStyle.compactSpacing) {
            Button { isTimelineExpanded.toggle() } label: {
                HStack(spacing: VyronWorkspaceStyle.compactSpacing) {
                    if isStreaming && activity.state == .working {
                        TimelineView(.periodic(from: activity.startedAt, by: 1)) { context in
                            Text(tracking.elapsedTitle(at: context.date)).monospacedDigit()
                        }
                    } else {
                        Text(tracking.elapsedTitle(at: activity.finishedAt ?? activity.latestRecordedAt))
                            .monospacedDigit()
                    }
                    Image(systemName: VyronSymbols.chevronRight)
                        .font(VyronConversationStyle.disclosure)
                        .rotationEffect(.degrees(isTimelineExpanded ? 90 : 0))
                    Spacer(minLength: 0)
                }
                .font(VyronConversationStyle.activity)
                .foregroundStyle(palette.muted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isTimelineExpanded ? VyronTrackingText.hideTimeline : VyronTrackingText.showTimeline)
            .accessibilityHint(isTimelineExpanded ? VyronTrackingText.hideTimeline : VyronTrackingText.showTimeline)
            Rectangle().fill(palette.border).frame(height: VyronWorkspaceStyle.dividerWidth)
        }
    }

    private var tracking: VyronTrackingPresentation {
        VyronTrackingPresentation(activity: activity, isLive: isStreaming)
    }

    private func statusRow(_ entry: ResponseActivity.Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: VyronConversationStyle.rowSpacing) {
            Image(systemName: statusSymbol)
                .font(VyronConversationStyle.icon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: VyronConversationStyle.rowSpacing) {
                Text(verbatim: entry.title)
                    .font(VyronConversationStyle.activity)
                    .fixedSize(horizontal: false, vertical: true)
                if activity.state == .failed || activity.state == .stopped,
                    let detail = entry.detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(VyronConversationStyle.detailTitle)
                        .textSelection(.enabled)
                }
            }
        }
        .foregroundStyle(activity.state == .failed ? palette.warning : palette.muted)
        .padding(.vertical, VyronConversationStyle.statusVerticalPadding)
        .accessibilityElement(children: .combine)
    }

    private var statusSymbol: String {
        switch activity.state {
        case .working: VyronSymbols.activityWorking
        case .completed: VyronSymbols.checkmark
        case .stopped: VyronSymbols.activityStopped
        case .failed: VyronSymbols.warning
        }
    }

    private func openTracking(entryID: UUID? = nil) {
        guard let conversationID = model.selectedConversationID else { return }
        model.openActivity(conversationID: conversationID, messageID: messageID, entryID: entryID)
    }
}
