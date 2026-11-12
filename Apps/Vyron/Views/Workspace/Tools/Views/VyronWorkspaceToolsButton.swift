import SwiftUI

struct VyronWorkspaceToolsButton: View {
    @EnvironmentObject private var library: VyronWorkspaceLibraryModel
    @EnvironmentObject private var presentation: VyronWorkspaceTabsPresentation
    @State private var isPresented = false
    @State private var pendingTool: (() -> Void)?

    var body: some View {
        Button { isPresented = true } label: {
            VyronWorkspaceHeaderIcon(symbol: VyronSymbols.tools)
        }
        .buttonStyle(.plain)
        .help(VyronToolsText.toolsTitle)
        .accessibilityLabel(VyronToolsText.toolsTitle)
        .sheet(isPresented: $isPresented, onDismiss: performPendingTool) {
            VStack(spacing: 0) {
                HStack {
                    Text(VyronToolsText.toolsTitle).font(VyronWorkspaceToolsStyle.titleFont)
                    Spacer()
                    Button(VyronToolsText.done) { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(VyronWorkspaceToolsStyle.padding)
                Divider()
                ScrollView {
                    VyronWorkspaceToolsView(performTool: { action in
                        pendingTool = action
                        isPresented = false
                    })
                        .padding(VyronWorkspaceToolsStyle.sectionSpacing)
                }
            }
            .frame(width: VyronWorkspaceToolsStyle.contentWidth, height: VyronWorkspaceToolsStyle.panelHeight)
            .background(Palette.canvas)
            .foregroundStyle(Palette.text)
            .environmentObject(library)
            .environmentObject(presentation)
        }
    }

    private func performPendingTool() {
        let action = pendingTool
        pendingTool = nil
        action?()
    }
}
