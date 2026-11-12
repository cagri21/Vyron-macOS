import SwiftUI

struct VyronModelScoreLabel: View {
    @Environment(\.locale) private var locale
    let score: Double?

    var body: some View {
        Text(
            score.map { VyronModelRankingText.score(VyronModelScorePresentation.points($0, locale: locale)) }
                ?? VyronModelRankingText.unrated
        )
        .font(VyronWorkspaceStyle.captionFont)
        .foregroundStyle(Palette.muted)
        .help(VyronModelRankingText.basis)
    }
}
