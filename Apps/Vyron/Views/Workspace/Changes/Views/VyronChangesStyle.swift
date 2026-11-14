import SwiftUI

enum VyronChangesStyle {
    static let codeFont = Font.system(size: 11, design: .monospaced)
    static let countFont = Font.system(size: 11).monospacedDigit()
    static let gutterWidth: CGFloat = 34
    static let markerWidth: CGFloat = 16
    static let indicatorWidth: CGFloat = 3
    static let lineHeight: CGFloat = 20
    static let rowHeight: CGFloat = 30
    static let listMaximumHeight: CGFloat = 200
    static let listWidth: CGFloat = 196
    static let sideBySideMinimumWidth: CGFloat = 520
    static let addedBackgroundOpacity = 0.13
    static let removedBackgroundOpacity = 0.15
    static let gutterOpacity = 0.55
}
