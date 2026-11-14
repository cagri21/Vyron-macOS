import SwiftUI

struct VyronUnifiedDiffRow: View {
    @Environment(\.vyronPalette) private var palette
    let line: VyronUnifiedDiffLine
    let filename: String
    let canScrollHorizontally: Bool

    var body: some View {
        HStack(spacing: 0) {
            if line.kind == .hunk || line.kind == .noNewline {
                Text(verbatim: line.text)
                    .foregroundStyle(line.kind == .hunk ? palette.diffHunk : palette.muted)
                    .lineLimit(1)
                    .padding(.horizontal, VyronWorkspaceStyle.controlSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Rectangle().fill(lineColor).frame(width: VyronChangesStyle.indicatorWidth)
                gutter
                Text(VyronDiffSyntax.highlight(
                    line.text.isEmpty ? " " : line.text, filename: filename, scheme: palette.scheme
                ))
                    .foregroundStyle(palette.codeText)
                    .lineLimit(1)
                    .fixedSize(horizontal: canScrollHorizontally, vertical: false)
                    .padding(.horizontal, VyronWorkspaceStyle.compactSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: VyronChangesStyle.lineHeight)
        .background(rowBackground)
        .accessibilityElement(children: .combine)
    }

    private var gutter: some View {
        HStack(spacing: 0) {
            number(line.oldNumber)
            number(line.newNumber)
            Text(verbatim: marker)
                .frame(width: VyronChangesStyle.markerWidth)
        }
        .monospacedDigit()
        .foregroundStyle(lineColor == .clear ? palette.muted : lineColor)
        .frame(maxHeight: .infinity)
        .background(palette.canvas.opacity(VyronChangesStyle.gutterOpacity))
    }

    private func number(_ value: Int?) -> some View {
        Text(verbatim: value.map(String.init) ?? "")
            .padding(.trailing, VyronWorkspaceStyle.compactSpacing)
            .frame(width: VyronChangesStyle.gutterWidth, alignment: .trailing)
    }

    private var marker: String {
        switch line.kind {
        case .added: "+"
        case .removed: "−"
        case .context, .hunk, .noNewline: ""
        }
    }

    private var lineColor: Color {
        switch line.kind {
        case .added: palette.diffAdded
        case .removed: palette.diffRemoved
        case .context, .hunk, .noNewline: .clear
        }
    }

    private var rowBackground: Color {
        switch line.kind {
        case .added: palette.diffAdded.opacity(VyronChangesStyle.addedBackgroundOpacity)
        case .removed: palette.diffRemoved.opacity(VyronChangesStyle.removedBackgroundOpacity)
        case .hunk: palette.field
        case .context, .noNewline: palette.canvas
        }
    }
}
