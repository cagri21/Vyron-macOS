// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronModelRankingText {
    static var basis: String {
        VyronResourceBundle.string("modelRankingBasis", fallback: "A local ranking for coding, using Vyron’s catalog, tools, model size, effort, and your model preference. Auto prefers higher points. These scores are not benchmark results.")
    }
    static var chatHelpers: String {
        VyronResourceBundle.string("modelRankingChatHelpers", fallback: "Chat helpers")
    }
    static func choice(_ p1: String, _ p2: String) -> String {
        VyronResourceBundle.format(
            "modelRankingChoice",
            fallback: "%@ · %@ pts",
            arguments: [p1, p2]
        )
    }
    static var otherModels: String {
        VyronResourceBundle.string("modelRankingOtherModels", fallback: "Other models")
    }
    static func score(_ p1: String) -> String {
        VyronResourceBundle.format(
            "modelRankingScore",
            fallback: "Auto score: %@",
            arguments: [p1]
        )
    }
    static var title: String {
        VyronResourceBundle.string("modelRankingTitle", fallback: "Coding Auto scores")
    }
    static var unrated: String {
        VyronResourceBundle.string("modelRankingUnrated", fallback: "Unrated")
    }
    static func unratedChoice(_ p1: String) -> String {
        VyronResourceBundle.format(
            "modelRankingUnratedChoice",
            fallback: "%@ · Unrated",
            arguments: [p1]
        )
    }
}
