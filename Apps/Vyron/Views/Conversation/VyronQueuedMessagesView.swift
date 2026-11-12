import SwiftUI

struct VyronQueuedMessagesView: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let _ = localizationLocale
        if !model.queuedMessages.isEmpty {
            Group {
                if model.queuedMessages.count > 3 {
                    ScrollView {
                        rows
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: VyronFollowUpStyle.maximumQueueHeight)
                } else {
                    rows
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(VyronQueueText.pendingMessages)
        }
    }

    private var rows: some View {
        VStack(spacing: VyronFollowUpStyle.rowSpacing) {
            ForEach(model.queuedMessages) { message in
                VyronQueuedMessageRow(message: message)
            }
        }
    }
}
