import SwiftUI

struct VyronConversationChangePreview: View {
    let path: String
    let diff: VyronUnifiedDiff

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: VyronConversationChangesStyle.cardRadius)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: VyronConversationChangesStyle.headerSpacing) {
                Text(verbatim: path)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 0)
                VyronDiffCountsView(added: diff.addedCount, removed: diff.removedCount)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(VyronConversationChangesStyle.actionFont)
            .padding(.horizontal, VyronConversationChangesStyle.headerInset)
            .frame(minHeight: VyronConversationChangesStyle.rowHeight)
            .background(Palette.field)
            Rectangle().fill(Palette.border).frame(height: VyronWorkspaceStyle.dividerWidth)
            VyronUnifiedDiffView(diff: diff, maximumLineCount: VyronConversationChangesStyle.previewLineCount)
        }
        .frame(maxWidth: .infinity)
        .background(Palette.canvas)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Palette.border) }
        .shadow(color: .black.opacity(0.40), radius: VyronConversationChangesStyle.previewShadowRadius)
    }
}
