import SwiftUI
import VyronCore

struct VyronConversationWindowMessageView: View {
    @Environment(\.vyronPalette) private var palette
    let message: ChatMessage
    let isStreaming: Bool
    let clarificationAnswers: [VyronClarificationAnswer]

    private var transcriptMessage: ChatMessage {
        var transcript = message
        // The main response view's inspector buttons belong to the main selection.
        // This independent window presents activity without changing that selection.
        transcript.activity = nil
        return transcript
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VyronWorkspaceStyle.compactSpacing) {
            if let activity = message.activity {
                let tracking = VyronTrackingPresentation(activity: activity, isLive: isStreaming)
                if isStreaming {
                    TimelineView(.periodic(from: activity.startedAt, by: 1)) { context in
                        Text(tracking.elapsedTitle(at: context.date)).monospacedDigit()
                    }
                    .font(VyronConversationWindowStyle.detail)
                    .foregroundStyle(palette.muted)
                } else {
                    Text(tracking.elapsedTitle(at: activity.finishedAt ?? activity.latestRecordedAt))
                        .monospacedDigit()
                        .font(VyronConversationWindowStyle.detail)
                        .foregroundStyle(palette.muted)
                }
                if let entry = activity.entries.last, isStreaming || activity.state != .completed {
                    Text(verbatim: entry.title)
                        .font(VyronConversationWindowStyle.detail)
                        .foregroundStyle(activity.state == .failed ? palette.warning : palette.muted)
                    if let detail = entry.detail, activity.state == .failed || activity.state == .stopped {
                        Text(verbatim: detail)
                            .font(VyronConversationWindowStyle.detail)
                            .foregroundStyle(palette.muted)
                            .textSelection(.enabled)
                    }
                }
            }
            VyronConversationMessageView(
                message: transcriptMessage, isStreaming: isStreaming, clarificationAnswers: clarificationAnswers
            )
        }
    }
}
