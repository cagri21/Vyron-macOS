import SwiftUI

enum VyronAppearanceSettingsStyle {
    static let rowHeight: CGFloat = 44
    static let pillHeight: CGFloat = 30
    static let pillInset: CGFloat = 10
    static let swatchSize: CGFloat = 13
    static let themeMarkSize: CGFloat = 20
    static let controlSpacing: CGFloat = 8
    static let modeSpacing: CGFloat = 12
    static let previewWidth: CGFloat = 78
    static let previewHeight: CGFloat = 52
    static let previewInset: CGFloat = 7
    static let previewSidebarWidth: CGFloat = 12
    static let previewWindowRadius: CGFloat = 4
    static let previewLineHeight: CGFloat = 2
    static let previewLineSpacing: CGFloat = 3
    static let popoverInset: CGFloat = 12
    static let popoverWidth: CGFloat = 252
    static let popoverListHeight: CGFloat = 306
    static let optionInset: CGFloat = 6
    static let pickerLabelWidth: CGFloat = 150
    static let controlText = VyronAppearanceTypography(size: 13)
    static let modeLabel = VyronAppearanceTypography(size: 11, weight: .medium)
    static let controlIcon = Font.system(size: 13)
    static let chevron = Font.system(size: 11, weight: .medium)
    static let themeMark = Font.system(size: 10, weight: .semibold)
}
