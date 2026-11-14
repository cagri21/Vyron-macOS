import SwiftUI

struct VyronDiffCountsView: View {
    let added: Int
    let removed: Int

    var body: some View {
        HStack(spacing: VyronWorkspaceStyle.composerHintKeyRadius) {
            Text(verbatim: "+\(added.formatted())")
                .foregroundStyle(Palette.diffAdded)
            Text(verbatim: "−\(removed.formatted())")
                .foregroundStyle(Palette.diffRemoved)
        }
        .font(VyronChangesStyle.countFont)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
