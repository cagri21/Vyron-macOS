import SwiftUI
import VyronCore

struct VyronActivityPanel: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @State private var showsSubagents = false
    private static let bottomAnchor = "activity-bottom"

    var body: some View {
        let _ = localizationLocale
        VStack(spacing: 0) {
            panelHeader
            Rectangle().fill(palette.border).frame(height: VyronTrackingStyle.dividerWidth)
            if let activity = model.trackedActivity {
                if let subagent = model.trackedSubagent {
                    workerHeader(subagent)
                    activityContent(
                        activity,
                        summary: activity.state == .stopped ? nil : subagent.summary,
                        prompt: subagent.identity.prompt
                    )
                } else if showsSubagents {
                    subagentList(activity.subagentActivities)
                } else {
                    activityContent(activity, summary: model.trackedMessage?.content, prompt: nil)
                }
            } else {
                emptyState(VyronTrackingText.noActivity, symbol: VyronSymbols.activityList)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.canvas)
        .onChange(of: model.appNavigation.trackingSelection) { previous, selection in
            if previous?.messageID != selection?.messageID || selection?.entryID != nil {
                showsSubagents = false
            }
        }
    }

    private var panelHeader: some View {
        HStack(spacing: VyronTrackingStyle.rowSpacing) {
            if model.trackedSubagent != nil {
                Button {
                    openParent()
                    showsSubagents = true
                } label: {
                    Image(systemName: VyronSymbols.back)
                }
                .buttonStyle(.plain)
                .help(VyronTrackingText.back)
                .accessibilityLabel(VyronTrackingText.back)
                Text(VyronTrackingText.subagents)
                    .font(VyronTrackingStyle.title)
            } else {
                sectionButton(VyronTrackingText.title, isSubagents: false)
                sectionButton(VyronTrackingText.subagents, isSubagents: true)
            }
            Spacer(minLength: 0)
            Button { model.closeActivity() } label: {
                Image(systemName: VyronSymbols.close)
            }
            .buttonStyle(.plain)
            .help(VyronTrackingText.close)
            .accessibilityLabel(VyronTrackingText.close)
        }
        .font(VyronTrackingStyle.icon)
        .foregroundStyle(palette.muted)
        .padding(.horizontal, VyronTrackingStyle.padding)
        .frame(height: VyronTrackingStyle.headerHeight)
    }

    private func sectionButton(_ title: String, isSubagents: Bool) -> some View {
        Button {
            showsSubagents = isSubagents
        } label: {
            HStack(spacing: VyronTrackingStyle.compactSpacing) {
                Text(title)
                if isSubagents, let count = model.trackedMessage?.activity?.subagentActivities.count, count > 0 {
                    Text(count, format: .number).monospacedDigit()
                }
            }
            .font(VyronTrackingStyle.title)
            .foregroundStyle(showsSubagents == isSubagents ? palette.text : palette.muted)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(showsSubagents == isSubagents ? .isSelected : [])
    }

    private func workerHeader(_ subagent: VyronSubagentActivity) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: VyronTrackingStyle.rowSpacing) {
            Image(systemName: VyronSymbols.subagents)
                .foregroundStyle(palette.accent)
            Text(verbatim: subagent.identity.name)
                .font(VyronTrackingStyle.title)
                .foregroundStyle(palette.text)
                .lineLimit(2)
            Spacer(minLength: 0)
            Text(verbatim: subagent.identity.model)
                .font(VyronTrackingStyle.caption)
                .foregroundStyle(palette.muted)
                .lineLimit(2)
                .help(subagent.identity.model)
        }
        .font(VyronTrackingStyle.icon)
        .padding(VyronTrackingStyle.padding)
    }

    private func activityContent(_ activity: ResponseActivity, summary: String?, prompt: String?) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: VyronTrackingStyle.sectionSpacing) {
                    activityHeader(activity)
                    if let prompt, !prompt.isEmpty {
                        DisclosureGroup(VyronTrackingText.prompt) {
                            Text(verbatim: prompt)
                                .font(VyronTrackingStyle.caption)
                                .textSelection(.enabled)
                                .padding(.top, VyronTrackingStyle.compactSpacing)
                        }
                        .font(VyronTrackingStyle.caption)
                        .foregroundStyle(palette.muted)
                    }
                    if !activity.subagentActivities.isEmpty {
                        Button {
                            showsSubagents = true
                        } label: {
                            Label(
                                VyronTrackingText.helpersStarted(activity.subagentActivities.count),
                                systemImage: VyronSymbols.subagents
                            )
                            .font(VyronTrackingStyle.activity)
                            .foregroundStyle(palette.muted)
                        }
                        .buttonStyle(.plain)
                    }
                    VyronActivityTrailView(
                        activity: activity,
                        summary: summary,
                        selectedEntryID: model.appNavigation.trackingSelection?.entryID,
                        revealID: model.appNavigation.trackingSelection?.revealID
                    )
                    if let summary, !summary.isEmpty, activity.state != .working {
                        VStack(alignment: .leading, spacing: VyronTrackingStyle.rowSpacing) {
                            Text(VyronTrackingText.result)
                                .font(VyronTrackingStyle.title)
                                .foregroundStyle(palette.muted)
                            MarkdownContent(content: summary)
                        }
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(VyronTrackingStyle.padding)
            }
            .onChange(of: model.appNavigation.trackingSelection, initial: true) { _, selection in
                if let entryID = selection?.entryID { proxy.scrollTo(entryID, anchor: .top) }
            }
            .onChange(of: activity.entries.last?.id) { _, _ in
                if activity.state == .working, model.appNavigation.trackingSelection?.entryID == nil {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
        }
    }

    private func activityHeader(_ activity: ResponseActivity) -> some View {
        let live = activity.state == .working
            && model.appNavigation.trackingSelection.map { model.isResponseActivityLive(messageID: $0.messageID) } == true
        let presentation = VyronTrackingPresentation(activity: activity, isLive: live)
        return VStack(alignment: .leading, spacing: VyronTrackingStyle.rowSpacing) {
            if live {
                TimelineView(.periodic(from: activity.startedAt, by: 1)) { context in
                    Text(presentation.elapsedTitle(at: context.date))
                        .font(VyronTrackingStyle.activity)
                        .monospacedDigit()
                }
            } else {
                Text(presentation.elapsedTitle(at: activity.finishedAt ?? activity.latestRecordedAt))
                    .font(VyronTrackingStyle.activity)
            }
            Text(presentation.phase).font(VyronTrackingStyle.caption)
            Rectangle().fill(palette.border).frame(height: VyronTrackingStyle.dividerWidth)
        }
        .foregroundStyle(activity.state == .failed ? palette.danger : palette.muted)
    }

    private func subagentList(_ subagents: [VyronSubagentActivity]) -> some View {
        ScrollView {
            if subagents.isEmpty {
                emptyState(VyronTrackingText.noSubagents, symbol: VyronSymbols.subagents)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(subagents) { subagent in
                        Button {
                            guard let selection = model.appNavigation.trackingSelection else { return }
                            model.openActivity(
                                conversationID: selection.conversationID,
                                messageID: selection.messageID,
                                subagentID: subagent.id
                            )
                        } label: {
                            let statusColor = subagent.activity.state == .failed ? palette.danger : palette.muted
                            HStack(alignment: .top, spacing: VyronTrackingStyle.rowSpacing) {
                                Image(systemName: VyronTrackingPresentation.stateSymbol(subagent.activity.state))
                                    .font(VyronTrackingStyle.icon)
                                    .foregroundStyle(statusColor)
                                VStack(alignment: .leading, spacing: VyronTrackingStyle.compactSpacing) {
                                    Text(verbatim: subagent.identity.name)
                                        .font(VyronTrackingStyle.title)
                                        .foregroundStyle(palette.text)
                                    Text(VyronTrackingPresentation.status(subagent.activity.state))
                                        .font(VyronTrackingStyle.caption)
                                        .foregroundStyle(statusColor)
                                    Text(verbatim: subagent.identity.prompt)
                                        .font(VyronTrackingStyle.caption)
                                        .foregroundStyle(palette.muted)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: VyronSymbols.chevronRight)
                                    .font(VyronConversationStyle.disclosure)
                                    .foregroundStyle(palette.muted)
                            }
                            .padding(.vertical, VyronTrackingStyle.padding)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(palette.border).frame(height: VyronTrackingStyle.dividerWidth)
                    }
                }
                .padding(.horizontal, VyronTrackingStyle.padding)
            }
        }
    }

    private func emptyState(_ title: String, symbol: String) -> some View {
        VStack(spacing: VyronTrackingStyle.rowSpacing) {
            Image(systemName: symbol).font(VyronTrackingStyle.icon)
            Text(title).font(VyronTrackingStyle.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(palette.muted)
        .padding(VyronTrackingStyle.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openParent() {
        guard let selection = model.appNavigation.trackingSelection else { return }
        model.openActivity(conversationID: selection.conversationID, messageID: selection.messageID)
    }
}
