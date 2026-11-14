import SwiftUI

enum VyronEffortStyle {
    static let popoverWidth: CGFloat = 256
    static let popoverPadding: CGFloat = 12
    static let popoverRadius: CGFloat = 18
    static let sectionSpacing: CGFloat = 12
    static let headerHeight: CGFloat = 18
    static let subtitleHeight: CGFloat = 16
    static let headerIconSize: CGFloat = 16
    static let headerTitleInset: CGFloat = 24
    static let controlMaximumWidth: CGFloat = 300
    static let controlHeight: CGFloat = 28
    static let controlSpacing: CGFloat = 8
    static let controlPadding: CGFloat = 14
    static let trackHeight: CGFloat = 24
    static let thumbDiameter: CGFloat = 28
    static let focusLineWidth: CGFloat = 1
    static let disabledOpacity: Double = 0.45
    static let selectionAnimationDuration: TimeInterval = 0.22
    static let selectionAnimation = Animation.easeOut(duration: selectionAnimationDuration)
    static let speedDetailSpacing: CGFloat = 4
    static let speedButtonHorizontalPadding: CGFloat = 8
    static let speedButtonVerticalPadding: CGFloat = 4
    static let speedSelectedOpacity: Double = 0.16
    static let speedCaption = Font.system(size: 11)
    static let sparkleOpacity: Double = 0.42
    static let sparkleOpacityVariation: Double = 0.12
    static let sparkleRadius: CGFloat = 0.6
    static let sparkleRadiusVariation: CGFloat = 0.2
    static let ultraDriftCount = 14
    static let ultraDriftRadius: CGFloat = 1.5
    static let ultraDriftGlowOpacity: Double = 0.34
    static let ultraDriftGlowRadius: CGFloat = 2.5
    static let ultraBurstCount = 16
    static let ultraBurstSize: CGFloat = 76
    static let ultraBurstRadius: CGFloat = 2.5
    static let ultraBurstDistance: CGFloat = 34
    static let ultraBurstDuration: TimeInterval = 0.62
    static let title = Font.system(size: 14)
    static let icon = Font.system(size: 13)
    static let control = VyronWorkspaceStyle.controlFont
    static let chevron = VyronWorkspaceStyle.captionFont
    static let sparklePositions: [CGPoint] = [
        CGPoint(x: 0.06, y: 0.30),
        CGPoint(x: 0.12, y: 0.68),
        CGPoint(x: 0.19, y: 0.23),
        CGPoint(x: 0.22, y: 0.48),
        CGPoint(x: 0.24, y: 0.86),
        CGPoint(x: 0.30, y: 0.62),
        CGPoint(x: 0.35, y: 0.34),
        CGPoint(x: 0.39, y: 0.75),
        CGPoint(x: 0.43, y: 0.19),
        CGPoint(x: 0.46, y: 0.54),
        CGPoint(x: 0.51, y: 0.82),
        CGPoint(x: 0.55, y: 0.27),
        CGPoint(x: 0.59, y: 0.60),
        CGPoint(x: 0.63, y: 0.39),
        CGPoint(x: 0.66, y: 0.72),
        CGPoint(x: 0.70, y: 0.52),
        CGPoint(x: 0.75, y: 0.83),
        CGPoint(x: 0.79, y: 0.32),
        CGPoint(x: 0.83, y: 0.66),
        CGPoint(x: 0.89, y: 0.24),
        CGPoint(x: 0.94, y: 0.58)
    ]
}
