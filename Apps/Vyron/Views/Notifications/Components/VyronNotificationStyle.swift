import SwiftUI

enum VyronNotificationStyle {
    static let bellSize: CGFloat = 28
    static let bellRadius: CGFloat = 7
    static let bellBorderWidth: CGFloat = 1.5
    static let bellUnreadSize: CGFloat = 6
    static let bellUnreadInset: CGFloat = 3
    static let unreadBorderWidth: CGFloat = 2
    static let listInset = VyronSidebarStyle.listInset
    static let headerInset = VyronSidebarStyle.headerInset
    static let headerSpacing: CGFloat = 8
    static let headerVerticalInset: CGFloat = 10
    static let sectionSpacing: CGFloat = 20
    static let sectionHeaderInset: CGFloat = 8
    static let sectionHeaderBottomInset: CGFloat = 6
    static let rowSpacing: CGFloat = 2
    static let rowHorizontalInset: CGFloat = 8
    static let rowVerticalInset: CGFloat = 8
    static let contentSpacing: CGFloat = 4
    static let titleSpacing: CGFloat = 4
    static let statusSpacing: CGFloat = 4
    static let indicatorSize: CGFloat = 12
    static let rowUnreadSize: CGFloat = 6
    static let projectMaximumWidth: CGFloat = 82
    static let emptySpacing: CGFloat = 10
    static let emptyInset: CGFloat = 20
    static let emptySymbolSize: CGFloat = 24
    static let storageErrorInset: CGFloat = 10
    static let refreshInterval: TimeInterval = 60
    static let bell = Font.system(size: 13, weight: .bold)
    static let heading = Font.system(size: 14, weight: .semibold)
    static let section = Font.system(size: 12)
    static let title = Font.system(size: 13)
    static let unreadTitle = Font.system(size: 13, weight: .medium)
    static let preview = Font.system(size: 12)
    static let detail = Font.system(size: 10)
    static let action = Font.system(size: 11)
    static let status = Font.system(size: 10, weight: .medium)
    static let emptySymbol = Font.system(size: emptySymbolSize, weight: .medium)
}
