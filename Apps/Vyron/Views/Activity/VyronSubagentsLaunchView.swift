import SwiftUI
import VyronCore

struct VyronSubagentsLaunchView: View {
    @Environment(\.vyronPalette) private var palette
    @EnvironmentObject private var model: AppModel
    let messageID: UUID
    let subagents: [VyronSubagentActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: VyronTrackingStyle.compactSpacing) {
            ForEach(subagents) { subagent in
                Button {
                    guard let conversationID = model.selectedConversationID else { return }
                    model.openActivity(
                        conversationID: conversationID,
                        messageID: messageID,
                        subagentID: subagent.id
                    )
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: VyronTrackingStyle.rowSpacing) {
                        Image(systemName: VyronSymbols.subagents)
                            .font(VyronConversationStyle.icon)
                            .frame(width: VyronTrackingStyle.iconWidth)
                            .accessibilityHidden(true)
                        if subagent.activity.state == .stopped || subagent.activity.state == .failed {
                            Text(verbatim: subagent.identity.name)
                            Text(VyronTrackingPresentation.status(subagent.activity.state))
                        } else {
                            Text(VyronTrackingText.helperStarted(subagent.identity.name))
                                .modifier(VyronActivityShimmerModifier(
                                    isActive: subagent.activity.state == .working
                                ))
                        }
                    }
                    .font(VyronTrackingStyle.activity)
                    .foregroundStyle(subagent.activity.state == .failed ? palette.danger : palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(VyronTrackingText.viewActivity)
                .accessibilityElement(children: .combine)
                .accessibilityHint(VyronTrackingText.viewActivity)
            }
        }
        .padding(.vertical, VyronConversationStyle.statusVerticalPadding)
    }
}
