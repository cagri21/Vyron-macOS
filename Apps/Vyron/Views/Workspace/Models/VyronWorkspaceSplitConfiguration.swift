import SwiftUI

struct VyronWorkspaceSplitConfiguration {
    let edge: HorizontalEdge
    let panelWidths: ClosedRange<CGFloat>
    let idealPanelWidth: CGFloat
    let minimumContentWidth: CGFloat

    static func sidebar(minimumContentWidth: CGFloat) -> Self {
        Self(
            edge: .leading,
            panelWidths: VyronWorkspaceStyle.minimumSidebarWidth...VyronWorkspaceStyle.maximumSidebarWidth,
            idealPanelWidth: VyronWorkspaceStyle.sidebarWidth,
            minimumContentWidth: minimumContentWidth
        )
    }

    static let inspector = Self(
        edge: .trailing,
        panelWidths: VyronWorkspaceStyle.minimumInspectorWidth...VyronWorkspaceStyle.maximumInspectorWidth,
        idealPanelWidth: VyronWorkspaceStyle.inspectorWidth,
        minimumContentWidth: VyronWorkspaceStyle.minimumConversationWidth
    )

    func canDockPanel(available: CGFloat) -> Bool {
        available >= minimumContentWidth + panelWidths.lowerBound + VyronWorkspaceStyle.dividerWidth
    }

    func overlayPanelWidth(preferred: CGFloat, available: CGFloat) -> CGFloat {
        let maximumWidth = min(panelWidths.upperBound, available - VyronWorkspaceStyle.dividerWidth)
        return max(0, min(max(preferred, panelWidths.lowerBound), maximumWidth))
    }

    func panelWidth(preferred: CGFloat, available: CGFloat) -> CGFloat {
        let availablePanelWidth = available - minimumContentWidth - VyronWorkspaceStyle.dividerWidth
        let maximumWidth = max(panelWidths.lowerBound, min(panelWidths.upperBound, availablePanelWidth))
        return min(max(preferred, panelWidths.lowerBound), maximumWidth)
    }

    func resizedPanelWidth(start: CGFloat, translation: CGFloat, available: CGFloat) -> CGFloat {
        let change = edge == .leading ? translation : -translation
        return panelWidth(preferred: start + change, available: available)
    }
}
