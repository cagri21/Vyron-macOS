import SwiftUI

enum VyronWorkspaceTerminalLayout {
    static func height(preferred: CGFloat, available: CGFloat) -> CGFloat {
        let maximumHeight = max(
            0,
            available - VyronWorkspaceStyle.minimumTerminalContentHeight - VyronWorkspaceStyle.dividerWidth
        )
        let minimumHeight = min(VyronWorkspaceStyle.minimumTerminalHeight, maximumHeight)
        return min(max(preferred, minimumHeight), maximumHeight)
    }

    static func resizedHeight(start: CGFloat, translation: CGFloat, available: CGFloat) -> CGFloat {
        height(preferred: start - translation, available: available)
    }
}
