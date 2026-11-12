import SwiftUI

enum VyronSettingsStyle {
    static let sidebarWidth: CGFloat = 280
    static let minimumContentWidth: CGFloat = 620
    static let minimumWidth = sidebarWidth + dividerWidth + minimumContentWidth
    static let minimumHeight: CGFloat = 700
    static let preferredWidth: CGFloat = 1080
    static let preferredHeight: CGFloat = 780
    static let contentWidth: CGFloat = 800
    static let contentPadding: CGFloat = 44
    static let modelManagerInset: CGFloat = 25
    static let contentTopPadding: CGFloat = 40
    static let sidebarPadding: CGFloat = 16
    static let sidebarTopPadding: CGFloat = 20
    static let sidebarSectionSpacing: CGFloat = 26
    static let sidebarRowSpacing: CGFloat = 2
    static let sidebarRowHeight: CGFloat = 34
    static let sidebarIconWidth: CGFloat = 18
    static let searchHeight: CGFloat = 36
    static let searchRadius: CGFloat = 18
    static let searchInset: CGFloat = 12
    static let sectionSpacing: CGFloat = 32
    static let headingSpacing: CGFloat = 18
    static let textSpacing: CGFloat = 4
    static let rowSpacing: CGFloat = 24
    static let rowPadding: CGFloat = 16
    static let rowInset: CGFloat = 18
    static let rowRadius: CGFloat = 8
    static let cardRadius: CGFloat = 16
    static let dividerWidth: CGFloat = 1
    static let controlWidth: CGFloat = 140
    static let title = Font.system(size: 28, weight: .semibold)
    static let sidebarTitle = Font.system(size: 18, weight: .semibold)
    static let sectionTitle = Font.system(size: 13, weight: .medium)
    static let body = Font.system(size: 13)
    static let detail = Font.system(size: 12)
    static let sidebarIcon = Font.system(size: 13)
}
