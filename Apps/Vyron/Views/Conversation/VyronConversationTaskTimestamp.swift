import SwiftUI

struct VyronConversationTaskTimestamp: View {
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(VyronTaskDatePresentation.label(
                for: date,
                relativeTo: context.date,
                locale: locale,
                timeZone: timeZone
            ))
            .font(VyronWorkspaceStyle.captionFont)
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
