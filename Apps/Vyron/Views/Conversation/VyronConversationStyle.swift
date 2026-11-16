import SwiftUI

enum VyronConversationStyle {
    static let turnSpacing: CGFloat = 28
    static let contentSpacing: CGFloat = 18
    static let proseLineSpacing: CGFloat = 5
    static let detailSpacing: CGFloat = 10
    static let rowSpacing: CGFloat = 8
    static let detailInset: CGFloat = 21
    static let detailRuleWidth: CGFloat = 1
    static let statusVerticalPadding: CGFloat = 2
    static let userHorizontalPadding: CGFloat = 16
    static let userVerticalPadding: CGFloat = 11
    static let userRadius: CGFloat = 18
    static let maximumUserWidth: CGFloat = 520
    static let sentImageSize: CGFloat = 80
    static let sentImageRadius: CGFloat = 10
    static let sentImageSpacing: CGFloat = 8
    static let clarificationAnswerSpacing: CGFloat = 7
    static let clarificationPairSpacing: CGFloat = 12
    static let copyTopPadding: CGFloat = 4
    static let copyFeedbackDuration: Duration = .milliseconds(1_500)
    static let prose = VyronAppearanceTypography(size: 14)
    static let markdownHeading = VyronAppearanceTypography(size: 17, weight: .semibold)
    static let markdownSubheading = VyronAppearanceTypography(size: 15, weight: .semibold)
    static let markdownSmallHeading = VyronAppearanceTypography(size: 13, weight: .semibold)
    static let activity = VyronAppearanceTypography(size: 13)
    static let detailTitle = VyronAppearanceTypography(size: 12)
    static let detail = Font.system(size: 11, design: .monospaced)
    static let icon = Font.system(size: 12)
    static let disclosure = Font.system(size: 9, weight: .medium)
    static let elapsed = VyronAppearanceTypography(size: 11)
}
