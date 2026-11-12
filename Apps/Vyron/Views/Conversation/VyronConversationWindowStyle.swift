import SwiftUI

enum VyronConversationWindowStyle {
    static let minimumWidth: CGFloat = 700
    static let minimumHeight: CGFloat = 500
    static let defaultWidth: CGFloat = 1000
    static let defaultHeight: CGFloat = 760
    static let contentInset: CGFloat = 24
    static let headerInset: CGFloat = 16
    static let messageSpacing: CGFloat = 24
    static let composerSpacing: CGFloat = 12
    static let composerRadius: CGFloat = 18
    static let actionSize: CGFloat = 32
    static let title = Font.system(size: 14, weight: .semibold)
    static let detail = Font.system(size: 12)
    static let action = Font.system(size: 13, weight: .semibold)
}
