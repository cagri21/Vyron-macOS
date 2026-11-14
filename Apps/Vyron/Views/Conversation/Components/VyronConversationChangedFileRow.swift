import SwiftUI
import VyronDevelopment

struct VyronConversationChangedFileRow: View {
    @State private var isHovered = false
    @State private var showsPreview = false
    @State private var dismissedPreview = false

    let change: DevelopmentChange
    let diff: VyronUnifiedDiff?
    let isSelected: Bool
    let open: () -> Void

    var body: some View {
        Button {
            dismissedPreview = true
            showsPreview = false
            open()
        } label: {
            HStack(spacing: VyronConversationChangesStyle.headerSpacing) {
                filePath.frame(maxWidth: .infinity, alignment: .leading)
                if let diff {
                    VyronDiffCountsView(added: diff.addedCount, removed: diff.removedCount)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .font(VyronConversationChangesStyle.actionFont)
            .padding(.horizontal, VyronConversationChangesStyle.headerInset)
            .frame(minHeight: VyronConversationChangesStyle.rowHeight)
            .background(
                isHovered || isSelected ? Palette.field : Color.clear,
                in: RoundedRectangle(cornerRadius: VyronConversationChangesStyle.cardRadius)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering in
            isHovered = hovering
            if !hovering {
                showsPreview = false
                dismissedPreview = false
            }
        }
        .task(id: isHovered) {
            guard isHovered else { return }
            do {
                try await Task.sleep(for: VyronConversationChangesStyle.hoverDelay)
                if !dismissedPreview { showsPreview = true }
            } catch {
                return
            }
        }
        .overlay {
            if showsPreview, let diff { preview(diff) }
        }
        .zIndex(showsPreview ? 1 : 0)
    }

    private var filePath: some View {
        let separator = change.path.lastIndex(of: "/")
        let directory = separator.map { String(change.path[...$0]) } ?? ""
        let filename = separator.map { String(change.path[change.path.index(after: $0)...]) } ?? change.path
        return HStack(spacing: 0) {
            if !directory.isEmpty {
                Text(verbatim: directory)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(Palette.text.opacity(0.75))
            }
            Text(verbatim: filename)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(Palette.text)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: change.path))
    }

    private func preview(_ diff: VyronUnifiedDiff) -> some View {
        GeometryReader { geometry in
            let viewport = geometry.bounds(of: .scrollView)
            let roomAbove = viewport.map { -$0.minY } ?? VyronConversationChangesStyle.previewPreferredRoom
            let roomBelow = viewport.map { $0.maxY - geometry.size.height } ?? 0
            let above = roomAbove >= roomBelow || roomAbove >= VyronConversationChangesStyle.previewPreferredRoom
            let gap = VyronConversationChangesStyle.previewGap
            let availableHeight = max(
                0,
                min(VyronConversationChangesStyle.previewPreferredRoom, (above ? roomAbove : roomBelow) - gap)
            )
            Color.clear.overlay(alignment: .top) {
                VyronConversationChangePreview(path: change.path, diff: diff)
                    .frame(maxHeight: availableHeight, alignment: .top)
                    .clipped()
                    .padding(.horizontal, VyronConversationChangesStyle.previewInset)
                    .alignmentGuide(.top) { dimensions in
                        above ? dimensions[.bottom] + gap : -geometry.size.height - gap
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
