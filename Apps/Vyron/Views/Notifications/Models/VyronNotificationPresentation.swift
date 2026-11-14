import SwiftUI

enum VyronNotificationPresentation {
    static func title(_ section: VyronNotificationSection) -> String {
        switch section {
        case .priority: VyronNotificationText.priority
        case .today: VyronNotificationText.today
        case .yesterday: VyronNotificationText.yesterday
        case .earlier: VyronNotificationText.older
        }
    }

    static func title(_ kind: VyronNotificationKind) -> String {
        switch kind {
        case .working: VyronNotificationText.working
        case .completed: VyronNotificationText.completed
        case .failed: VyronNotificationText.failed
        case .attention: VyronNotificationText.needsAttention
        }
    }

    static func symbol(_ kind: VyronNotificationKind) -> String {
        switch kind {
        case .working: VyronSymbols.activityWorking
        case .completed: VyronSymbols.checkmark
        case .failed: VyronSymbols.warning
        case .attention: VyronSymbols.hand
        }
    }

    static func color(_ kind: VyronNotificationKind, palette: VyronAppearancePalette) -> Color {
        switch kind {
        case .working, .completed: palette.muted
        case .failed, .attention: palette.warning
        }
    }
}
