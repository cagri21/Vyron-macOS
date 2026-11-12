import SwiftUI

struct VyronWorkspaceToolsGrid: View {
    @Environment(\.locale) private var localizationLocale
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    @State private var showsMoreTools = false
    let newPage: () -> Void
    var performTool: (@escaping () -> Void) -> Void = { $0() }

    var body: some View {
        let _ = localizationLocale
        let availability = model.workspaceToolAvailability
        VStack(alignment: .leading, spacing: VyronWorkspaceToolsStyle.gridSpacing) {
            Text(VyronToolsText.toolsTitle)
                .font(VyronWorkspaceToolsStyle.titleFont)
                .padding(.bottom, VyronWorkspaceToolsStyle.gridSpacing)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: VyronWorkspaceToolsStyle.gridSpacing
            ) {
                tool(VyronToolsText.changes, symbol: VyronSymbols.changes, availability: availability) {
                    performTool { model.openWorkspaceTool(.changes) }
                }
                tool(VyronToolsText.terminal, symbol: VyronSymbols.terminal, availability: availability) {
                    performTool { model.openWorkspaceTool(.terminal) }
                }
                .help(availability.projectToolsEnabled ? VyronToolsText.terminalHint : VyronToolsText.workOnlyHint)
                tool(VyronToolsText.files, symbol: VyronSymbols.files, availability: availability) {
                    performTool { model.openWorkspaceTool(.files) }
                }
                Button {
                    performTool {
                        guard let sourceID = model.workspaceToolAvailability.sideChatConversationID,
                            let sideChatID = model.newSideChat(from: sourceID)
                        else { return }
                        openWindow(id: VyronAppWindow.conversation, value: sideChatID)
                    }
                } label: {
                    toolLabel(VyronToolsText.sideChat, symbol: VyronSymbols.sideChat)
                }
                .disabled(availability.sideChatConversationID == nil)
                .help(VyronToolsText.sideChatHint)
                Button(action: newPage) {
                    toolLabel(VyronToolsText.newPage, symbol: VyronSymbols.newPage)
                }
                moreTools
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.text)
    }

    private func tool(
        _ title: String,
        symbol: String,
        availability: VyronWorkspaceToolAvailability,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            toolLabel(title, symbol: symbol)
        }
        .disabled(!availability.projectToolsEnabled)
        .help(availability.projectToolsEnabled ? title : VyronToolsText.workOnlyHint)
    }

    private func toolLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: VyronWorkspaceToolsStyle.gridSpacing) {
            Image(systemName: symbol)
                .frame(width: VyronWorkspaceToolsStyle.iconWidth)
                .foregroundStyle(Palette.muted)
            Text(title)
            Spacer(minLength: 0)
        }
        .font(VyronWorkspaceToolsStyle.controlFont)
        .padding(.horizontal, VyronWorkspaceToolsStyle.padding)
        .frame(maxWidth: .infinity, minHeight: VyronWorkspaceToolsStyle.toolHeight)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: VyronWorkspaceToolsStyle.cornerRadius))
        .contentShape(RoundedRectangle(cornerRadius: VyronWorkspaceToolsStyle.cornerRadius))
    }

    private var moreTools: some View {
        Button { showsMoreTools.toggle() } label: {
            toolLabel(VyronToolsText.moreTools, symbol: VyronSymbols.tools)
                .overlay(alignment: .trailing) {
                    Image(systemName: VyronSymbols.chevronDown)
                        .font(VyronWorkspaceToolsStyle.controlFont)
                        .foregroundStyle(Palette.muted)
                        .padding(.trailing, VyronWorkspaceToolsStyle.padding)
                }
        }
        .popover(isPresented: $showsMoreTools) {
            VStack(alignment: .leading, spacing: VyronWorkspaceToolsStyle.gridSpacing) {
                moreTool(VyronWorkspaceText.plugins) { model.openPlugins() }
                moreTool(VyronScheduledTaskText.scheduledTasks) { model.appNavigation.showScheduledTasks = true }
                moreTool(VyronWorkspaceText.advancedTools) { model.appNavigation.showAutomation = true }
            }
            .font(VyronWorkspaceToolsStyle.controlFont)
            .padding(VyronWorkspaceToolsStyle.padding)
            .frame(minWidth: VyronWorkspaceToolsStyle.moreToolsWidth)
        }
    }

    private func moreTool(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            showsMoreTools = false
            performTool(action)
        } label: {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: VyronWorkspaceToolsStyle.toolHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
