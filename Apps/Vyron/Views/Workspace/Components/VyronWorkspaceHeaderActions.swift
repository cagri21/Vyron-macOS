import SwiftUI

struct VyronWorkspaceHeaderActions: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @State private var showsOverview = false
    var showConversation: () -> Void = {}

    var body: some View {
        let _ = localizationLocale
        HStack(spacing: VyronWorkspaceHeaderStyle.controlSpacing) {
            VyronWorkspaceChatMenu(conversationID: model.selectedConversationID)
            overviewControl
            inspectorControl
        }
    }

    private var overviewControl: some View {
        Button {
            showConversation()
            showsOverview.toggle()
        } label: {
            VyronWorkspaceHeaderIcon(symbol: VyronSymbols.taskOverview)
        }
        .buttonStyle(.plain)
        .help(VyronHeaderText.overview)
        .accessibilityLabel(VyronHeaderText.overview)
        .popover(isPresented: $showsOverview, arrowEdge: .top) {
            VyronTaskOverviewView()
        }
    }

    private var inspectorControl: some View {
        Button {
            showConversation()
            model.toggleWorkspaceInspector()
        } label: {
            VyronWorkspaceHeaderIcon(symbol: VyronSymbols.inspectorRight)
                .opacity(model.canToggleWorkspaceInspector ? 1 : VyronWorkspaceHeaderStyle.disabledOpacity)
        }
        .buttonStyle(.plain)
        .disabled(!model.canToggleWorkspaceInspector)
        .help(isInspectorVisible ? VyronHeaderText.hideInspector : VyronHeaderText.showInspector)
        .accessibilityLabel(isInspectorVisible ? VyronHeaderText.hideInspector : VyronHeaderText.showInspector)
        .accessibilityAddTraits(isInspectorVisible ? .isSelected : [])
    }

    private var isInspectorVisible: Bool {
        model.isWorkspaceInspectorVisible
    }
}
