import SwiftUI
import VyronCore

struct VyronWorkspaceChatMenu: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    let conversationID: UUID?
    @State private var showsRename = false
    @State private var renameConversationID: UUID?
    @State private var renameInitialTitle = ""
    @State private var schedulingTemplate: VyronChatSchedulingTemplate?

    var body: some View {
        let _ = localizationLocale
        let availability = conversationID.flatMap { model.chatActions(for: $0) }
        Menu {
            if let availability {
                VyronChatMenuActions(
                    availability: availability,
                    usesKeyboardShortcuts: true,
                    rename: { selection in
                        renameConversationID = selection.conversationID
                        renameInitialTitle = selection.title
                        showsRename = true
                    },
                    schedule: { schedulingTemplate = $0 }
                )
            }
        } label: {
            Image(systemName: VyronSymbols.chatActions)
                .font(VyronWorkspaceHeaderStyle.icon)
                .foregroundStyle(palette.text)
                .frame(width: VyronWorkspaceHeaderStyle.controlSize, height: VyronWorkspaceHeaderStyle.controlSize)
                .contentShape(Rectangle())
                .opacity(availability == nil ? VyronWorkspaceHeaderStyle.disabledOpacity : 1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(palette.text)
        .fixedSize()
        .disabled(availability == nil)
        .help(VyronHeaderText.actions)
        .accessibilityLabel(VyronHeaderText.actions)
        .sheet(isPresented: $showsRename) {
            if let id = renameConversationID {
                VyronSidebarNameEditor(title: VyronHeaderText.renameTitle, initialValue: renameInitialTitle) { title in
                    model.renameChat(id, title: title) ? nil : (model.errorMessage ?? VyronSidebarText.saveFailure)
                }
            }
        }
        .sheet(item: $schedulingTemplate) { template in
            VyronScheduledTaskEditor(
                initial: nil,
                context: template.definition.context,
                save: model.scheduledTasks.save,
                template: template.definition
            )
        }
    }
}
