import SwiftUI
import VyronCore

struct VyronActivityToolsView: View {
    @Environment(\.locale) private var localizationLocale
    let group: VyronActivityToolGroup
    let isCurrent: Bool
    let onInspect: (UUID) -> Void
    @State private var isExpanded = false

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronTrackingStyle.compactSpacing) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: VyronConversationStyle.rowSpacing) {
                    Image(systemName: VyronSymbols.activityTools)
                        .font(VyronConversationStyle.icon)
                        .accessibilityHidden(true)
                    Text(verbatim: group.summary)
                        .font(VyronConversationStyle.activity)
                        .fixedSize(horizontal: false, vertical: true)
                        .modifier(VyronActivityShimmerModifier(isActive: isCurrent))
                    Image(systemName: isExpanded ? VyronSymbols.chevronDown : VyronSymbols.chevronRight)
                        .font(VyronConversationStyle.disclosure)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? VyronAppText.activityExpanded : VyronAppText.activityCollapsed)
            .accessibilityHint(isExpanded ? VyronAppText.activityHideDetails : VyronAppText.activityShowDetails)
            .help(isExpanded ? VyronAppText.activityHideDetails : VyronAppText.activityShowDetails)
            .foregroundStyle(Palette.muted)
            .padding(.vertical, VyronConversationStyle.statusVerticalPadding)

            if isExpanded {
                VStack(alignment: .leading, spacing: VyronTrackingStyle.compactSpacing) {
                    ForEach(group.entries) { entry in
                        Button {
                            onInspect(entry.id)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: VyronConversationStyle.rowSpacing) {
                                Image(systemName: VyronTrackingPresentation.symbol(entry))
                                    .font(VyronConversationStyle.icon)
                                    .frame(width: VyronTrackingStyle.iconWidth)
                                    .accessibilityHidden(true)
                                Text(verbatim: entry.title)
                                    .font(VyronConversationStyle.activity)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(Palette.muted)
                            .padding(.vertical, VyronConversationStyle.statusVerticalPadding)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(entry.detail ?? entry.title)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}
