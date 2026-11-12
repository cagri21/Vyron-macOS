import SwiftUI

enum VyronAutomationTypography {
    static let title = Font.system(size: 28, weight: .regular, design: .serif)
    static let body = Font.system(size: 11)
    static let emphasizedBody = Font.system(size: 11, weight: .medium)
    static let caption = Font.system(size: 10)
    static let emphasizedCaption = Font.system(size: 10, weight: .medium)
    static let smallCaption = Font.system(size: 9)
    static let tinyCaption = Font.system(size: 8)
    static let agentInstruction = Font.system(size: 13)
    static let monospacedBody = Font.system(size: 11, design: .monospaced)
    static let monospacedMetric = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let monospacedCaption = Font.system(size: 10, design: .monospaced)
    static let monospacedSmallCaption = Font.system(size: 9, design: .monospaced)
    static let monospacedTinyCaption = Font.system(size: 8, design: .monospaced)
    static let proposalHeading = Font.system(size: 9, weight: .semibold, design: .monospaced)
    static let closeIcon = Font.system(size: 12)
    static let emptySnapshotIcon = Font.system(size: 23, weight: .ultraLight)
}
