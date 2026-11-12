import Foundation
import VyronCore

enum VyronModelScorePresentation {
    static func points(_ score: Double, locale: Locale = .current) -> String {
        score.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    static func choice(_ ranked: VyronScoredModel, locale: Locale = .current) -> String {
        VyronModelRankingText.choice(ranked.model.name, points(ranked.score, locale: locale))
    }
}
