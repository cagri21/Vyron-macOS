import Foundation
import SwiftUI
import VyronDevelopment

struct VyronInspectorChangeFileRow: View {
    let change: DevelopmentChange
    let isSelected: Bool
    let select: () -> Void

    @State private var diff: VyronUnifiedDiff?
    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: VyronWorkspaceStyle.compactSpacing) {
                Image(systemName: change.before == nil ? VyronSymbols.outputs : VyronSymbols.files)
                    .foregroundStyle(change.before == nil ? Palette.diffAdded : Palette.muted)
                    .accessibilityHidden(true)
                Text(verbatim: URL(fileURLWithPath: change.path).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isSelected ? Palette.controlAccent : Palette.text)
                Spacer(minLength: 0)
                if let diff {
                    VyronDiffCountsView(added: diff.addedCount, removed: diff.removedCount)
                }
            }
            .frame(height: VyronChangesStyle.rowHeight)
            .padding(.horizontal, VyronWorkspaceStyle.compactSpacing)
            .contentShape(Rectangle())
            .background(
                isSelected || isHovering ? Palette.field : .clear,
                in: RoundedRectangle(cornerRadius: VyronWorkspaceStyle.composerHintKeyRadius)
            )
            .padding(.horizontal, VyronWorkspaceStyle.compactSpacing)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(change.path)
        .accessibilityLabel(change.path)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task(id: VyronDiffRevision(change)) {
            diff = nil
            let change = change
            let result = await Task.detached { VyronUnifiedDiff(change: change, maximumLineCount: 0) }.value
            if !Task.isCancelled { diff = result }
        }
    }
}
