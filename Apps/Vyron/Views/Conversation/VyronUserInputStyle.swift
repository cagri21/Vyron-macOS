import SwiftUI

enum VyronUserInputStyle {
    static let sectionSpacing: CGFloat = 12
    static let questionSpacing = VyronConversationStyle.contentSpacing
    static let rowSpacing: CGFloat = 4
    static let controlSpacing = VyronWorkspaceStyle.compactSpacing
    static let padding = VyronWorkspaceStyle.composerPadding
    static let radius = VyronWorkspaceStyle.composerRadius
    static let rowRadius: CGFloat = 8
    static let rowHorizontalPadding: CGFloat = 8
    static let rowVerticalPadding: CGFloat = 6
    static let numberSize: CGFloat = 20
    static let numberRadius: CGFloat = 4
    static let actionSize: CGFloat = 28
    static let actionHorizontalPadding: CGFloat = 12
    static let actionVerticalPadding: CGFloat = 6
    static let maximumQuestionsHeight: CGFloat = 264
    static let question = Font.system(size: 13)
    static let option = VyronWorkspaceStyle.controlFont
    static let description = VyronWorkspaceStyle.captionFont
    static let input = Font.system(size: 13)
    static let number = Font.system(size: 11, design: .monospaced)
    static let icon = Font.system(size: 12)
}
