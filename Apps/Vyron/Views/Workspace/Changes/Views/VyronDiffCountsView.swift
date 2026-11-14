import SwiftUI

struct VyronDiffCountsView: View {
    @Environment(\.vyronPalette) private var palette
    let added: Int
    let removed: Int

    var body: some View {
        HStack(spacing: VyronWorkspaceStyle.composerHintKeyRadius) {
            Text(verbatim: "+\(added.formatted())")
                .foregroundStyle(palette.diffAdded)
            Text(verbatim: "−\(removed.formatted())")
                .foregroundStyle(palette.diffRemoved)
        }
        .font(VyronChangesStyle.countFont)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
