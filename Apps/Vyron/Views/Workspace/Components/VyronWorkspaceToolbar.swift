import SwiftUI

struct VyronWorkspaceToolbar: ToolbarContent {
    @EnvironmentObject private var model: AppModel
    @Binding var showSidebar: Bool
    var showConversation: () -> Void = {}

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if model.appNavigation.destination == .workspace {
                VyronWorkspaceNavigationControls(showSidebar: $showSidebar)
            }
        }
        .vyronPlainStyle()
        if model.appNavigation.destination == .workspace {
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.flexible, placement: .primaryAction)
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Spacer(minLength: 0)
                }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if model.appNavigation.destination == .workspace {
                VyronWorkspaceHeaderActions(showConversation: showConversation)
            }
        }
        .vyronPlainStyle()
    }
}
