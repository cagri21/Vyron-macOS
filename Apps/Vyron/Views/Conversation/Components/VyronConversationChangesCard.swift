import SwiftUI
import VyronDevelopment

struct VyronConversationChangesCard: View {
    @Environment(\.locale) private var localizationLocale
    @State private var previews: [UUID: VyronUnifiedDiff] = [:]

    let changes: [DevelopmentChange]
    let actions: VyronConversationChangesActions
    var selectedPath: String?

    var body: some View {
        let _ = localizationLocale
        if !changes.isEmpty {
            let shape = RoundedRectangle(cornerRadius: VyronConversationChangesStyle.cardRadius)
            VStack(alignment: .leading, spacing: 0) {
                header
                Rectangle().fill(Palette.border).frame(height: VyronWorkspaceStyle.dividerWidth)
                ForEach(changes) { change in
                    VyronConversationChangedFileRow(
                        change: change,
                        diff: previews[change.id],
                        isSelected: change.path == selectedPath
                    ) {
                        actions.reviewFile(change)
                    }
                }
            }
            .background(Palette.canvas, in: shape)
            .overlay { shape.strokeBorder(Palette.border).allowsHitTesting(false) }
            .task(id: changes.map(\.id)) { await preparePreviews() }
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: VyronConversationChangesStyle.headerSpacing) {
                heading
                Spacer(minLength: 0)
                actionButtons
            }
            VStack(alignment: .leading, spacing: VyronConversationChangesStyle.headerSpacing) {
                heading
                actionButtons.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(VyronConversationChangesStyle.headerInset)
        .background(Palette.surface, in: UnevenRoundedRectangle(
            topLeadingRadius: VyronConversationChangesStyle.cardRadius,
            topTrailingRadius: VyronConversationChangesStyle.cardRadius
        ))
    }

    private var heading: some View {
        HStack(spacing: VyronConversationChangesStyle.headerSpacing) {
            VStack(spacing: 0) {
                Image(systemName: VyronSymbols.plus)
                Image(systemName: VyronSymbols.minus)
            }
            .font(VyronConversationChangesStyle.changeGlyphFont)
            .foregroundStyle(Palette.muted)
            .frame(
                width: VyronConversationChangesStyle.changeGlyphSize,
                height: VyronConversationChangesStyle.changeGlyphSize
            )
            .background {
                RoundedRectangle(cornerRadius: VyronConversationChangesStyle.changeGlyphRadius)
                    .strokeBorder(Palette.muted, lineWidth: VyronWorkspaceStyle.dividerWidth)
            }
            .frame(
                width: VyronConversationChangesStyle.headerIconSize,
                height: VyronConversationChangesStyle.headerIconSize
            )
            .background(
                Palette.sidebar, in: RoundedRectangle(cornerRadius: VyronConversationChangesStyle.headerIconRadius)
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: VyronWorkspaceStyle.compactSpacing) {
                Text(VyronConversationChangesText.editedFiles(changes.count))
                    .font(VyronConversationChangesStyle.titleFont)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                if previews.count == changes.count {
                    VyronDiffCountsView(
                        added: previews.values.reduce(0) { $0 + $1.addedCount },
                        removed: previews.values.reduce(0) { $0 + $1.removedCount }
                    )
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var actionButtons: some View {
        HStack(spacing: VyronConversationChangesStyle.headerSpacing) {
            if let undo = actions.undo {
                Button(action: undo) {
                    HStack(spacing: VyronWorkspaceStyle.compactSpacing) {
                        Text(VyronConversationChangesText.undoChanges)
                        Image(systemName: VyronSymbols.effortReset)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(QuietButtonStyle(foreground: Palette.text))
            }
            Button(action: actions.viewChanges) {
                let shape = RoundedRectangle(cornerRadius: VyronConversationChangesStyle.actionRadius)
                Text(VyronConversationChangesText.viewChanges)
                    .padding(.horizontal, VyronConversationChangesStyle.actionInset)
                    .frame(minHeight: VyronConversationChangesStyle.actionHeight)
                    .background(Palette.selection, in: shape)
                    .overlay { shape.strokeBorder(Palette.border).allowsHitTesting(false) }
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
        }
        .font(VyronConversationChangesStyle.actionFont)
        .foregroundStyle(Palette.text)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func preparePreviews() async {
        let pending = changes.filter { previews[$0.id] == nil }
        if pending.isEmpty, previews.count == changes.count { return }
        let result = await withTaskGroup(of: [UUID: VyronUnifiedDiff].self) { group in
            group.addTask(priority: .utility) {
                var result: [UUID: VyronUnifiedDiff] = [:]
                for change in pending {
                    guard !Task.isCancelled else { return [:] }
                    result[change.id] = VyronUnifiedDiff(
                        change: change,
                        maximumLineCount: VyronConversationChangesStyle.previewLineCount
                    )
                }
                return result
            }
            return await group.next() ?? [:]
        }
        guard !Task.isCancelled else { return }
        let activeIDs = Set(changes.map(\.id))
        previews = previews.filter { activeIDs.contains($0.key) }.merging(result) { _, current in current }
    }
}
