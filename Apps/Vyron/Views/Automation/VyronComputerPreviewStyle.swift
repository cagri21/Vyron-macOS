import SwiftUI

enum VyronComputerPreviewStyle {
    static let spacing = VyronWorkspaceStyle.controlSpacing
    static let compactSpacing = VyronWorkspaceStyle.compactSpacing
    static let padding = VyronWorkspaceStyle.composerPadding
    static let radius = VyronWorkspaceStyle.contextRadius
    static let title = VyronWorkspaceStyle.controlFont
    static let caption = VyronWorkspaceStyle.captionFont
    static let height: CGFloat = 240
    static let highlightWidth: CGFloat = 3
    static let highlightRadius: CGFloat = 6
    static let highlightInset: CGFloat = 5
    static let pointerSize: CGFloat = 28
    static let pointerOutline: CGFloat = 1.5
    static let pointerFont: Font = .system(size: 15, weight: .semibold)
    static let badgeWidth: CGFloat = 280
    static let badgeHeight: CGFloat = 44
    static let badgeScreenInset: CGFloat = 20
    static let overlayLifetime: Duration = .milliseconds(1_200)
    static let actionVisibilitySeconds: TimeInterval = 3
    static let refreshInterval: Duration = .seconds(1)
}
