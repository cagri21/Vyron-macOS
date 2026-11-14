import SwiftUI

struct VyronUnifiedDiffView: View {
    @Environment(\.vyronPalette) private var palette
    let diff: VyronUnifiedDiff
    var maximumLineCount: Int?

    var body: some View {
        Group {
            if let maximumLineCount {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(diff.lines.prefix(maximumLineCount).indices, id: \.self) { index in
                        VyronUnifiedDiffRow(line: diff.lines[index], filename: diff.filename, canScrollHorizontally: false)
                    }
                }
            } else {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(diff.lines.indices, id: \.self) { index in
                                VyronUnifiedDiffRow(
                                    line: diff.lines[index], filename: diff.filename, canScrollHorizontally: true
                                )
                            }
                        }
                        .frame(minWidth: geometry.size.width, alignment: .leading)
                        .textSelection(.enabled)
                    }
                }
            }
        }
        .font(VyronChangesStyle.codeFont)
        .background(palette.canvas)
    }
}
