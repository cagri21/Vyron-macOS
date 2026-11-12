import SwiftUI

enum VyronWorkspaceTabsStyle {
    static let tabHeight: CGFloat = 34
    static let tabWidth: CGFloat = 180
    static let minimumTabWidth: CGFloat = 110
    static let tabBarHeight: CGFloat = 42
    static let chromeHeight: CGFloat = 46
    static let controlSize: CGFloat = 28
    static let spacing: CGFloat = 8
    static let compactSpacing: CGFloat = 4
    static let padding: CGFloat = 12
    static let radius: CGFloat = 9
    static let addressRadius: CGFloat = 17
    static let minimumAddressWidth: CGFloat = 160
    static let titleFont = Font.system(size: 12)
    static let addressFont = Font.system(size: 13)
    static let pageTitleFont = Font.system(size: 24, weight: .medium)
    static let pageBodyFont = Font.system(size: 14)
    static let disabledOpacity = 0.4

    static func tabItemWidth(containerWidth: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return tabWidth }
        let available = containerWidth - controlSize - spacing - compactSpacing * 2
        let gaps = CGFloat(count - 1) * compactSpacing
        return max(minimumTabWidth, min(tabWidth, (available - gaps) / CGFloat(count)))
    }
}
