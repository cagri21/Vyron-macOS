import AppKit
import SwiftUI
import VyronCore

/// Shared contents for the title-bar menu and the captured sidebar chat's context menu.
struct VyronChatMenuActions: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    let availability: VyronChatActionAvailability
    let usesKeyboardShortcuts: Bool
    let rename: (VyronChatActionAvailability) -> Void
    let schedule: (VyronChatSchedulingTemplate) -> Void

    var body: some View {
        let id = availability.conversationID
        Button {
            rename(availability)
        } label: {
            Label(VyronHeaderText.rename, systemImage: VyronSymbols.pencil)
        }
        .disabled(!availability.canRename)
        .keyboardShortcut(shortcut("r", modifiers: [.command, .option]))
        Button { model.toggleChatPin(id) } label: {
            Label(
                availability.isPinned ? VyronHeaderText.unpin : VyronHeaderText.pin,
                systemImage: availability.isPinned ? VyronSymbols.unpin : VyronSymbols.pin
            )
        }
        .disabled(!availability.canPin)
        .keyboardShortcut(shortcut("p", modifiers: [.command, .option]))
        Button { model.markChatUnread(id) } label: {
            Label(VyronHeaderText.markUnread, systemImage: VyronSymbols.markUnread)
        }
        .keyboardShortcut(shortcut("u", modifiers: [.command, .shift]))
        Menu {
            sectionChoices(id)
        } label: {
            Label(VyronHeaderText.section, systemImage: VyronSymbols.section)
        }
        Divider()
        Button {
            if let sideChatID = model.newSideChat(from: id) {
                openWindow(id: VyronAppWindow.conversation, value: sideChatID)
            }
        } label: {
            Label(VyronHeaderText.newSideChat, systemImage: VyronSymbols.sideChat)
        }
        .disabled(!model.canCreateSideChat(from: id))
        Menu {
            Button(VyronHeaderText.continueChat) { model.continueChat(id, in: .chat) }
                .disabled(!model.canContinueChat(id))
            Button(VyronHeaderText.continueWork) { model.continueChat(id, in: .agent) }
                .disabled(!model.canContinueChat(id))
            Button(VyronHandoffText.title) { model.presentChatHandoff(from: id) }
        } label: {
            Label(VyronHeaderText.continueIn, systemImage: VyronSymbols.fork)
        }
        .disabled(!availability.canContinue)
        Button {
            if let template = model.chatSchedulingTemplate(for: id) { schedule(template) }
        } label: {
            Label(VyronHeaderText.scheduleTask, systemImage: VyronSymbols.schedule)
        }
        .disabled(model.chatSchedulingTemplate(for: id) == nil)
        Divider()
        if let exported = model.chatExport(for: id) {
            ShareLink(item: exported.text) {
                Label(VyronHeaderText.share, systemImage: VyronSymbols.share)
            }
            .disabled(!availability.canExport)
        }
        Menu {
            Button(VyronHeaderText.copyDeeplink) { copy(model.chatDeepLink(for: id)?.absoluteString) }
                .keyboardShortcut(shortcut("l", modifiers: [.command, .option]))
            Button(VyronHeaderText.copyMarkdown) { copy(model.chatExport(for: id)?.markdown) }
            Button(VyronHeaderText.copyText) { copy(model.chatExport(for: id)?.plainText) }
            Button(VyronHeaderText.copyWorkingDirectory) { copy(model.chatWorkingDirectory(for: id)) }
                .disabled(model.chatWorkingDirectory(for: id) == nil)
                .keyboardShortcut(shortcut("c", modifiers: [.command, .shift]))
        } label: {
            Label(VyronHeaderText.copy, systemImage: VyronSymbols.copy)
        }
        .disabled(!availability.canExport)
        Button {
            guard model.chatActions(for: id)?.canExport == true else { return }
            openWindow(id: VyronAppWindow.conversation, value: id)
        } label: {
            Label(VyronHeaderText.openNewWindow, systemImage: VyronSymbols.openWindow)
        }
        .disabled(!availability.canExport)
        Menu {
            Button(VyronHeaderText.openProjectFinder) { model.openChatProjectInFinder(id) }
                .disabled(model.chatProjectURL(for: id) == nil)
            Button(VyronHeaderText.openProjectXcode) { model.openChatProjectInXcode(id) }
                .disabled(!model.canOpenChatProjectInXcode(id))
        } label: {
            Label(VyronHeaderText.openIn, systemImage: VyronSymbols.externalOpen)
        }
        .disabled(model.chatProjectURL(for: id) == nil)
        Divider()
        Button { model.archiveChat(id) } label: {
            Label(VyronHeaderText.archive, systemImage: VyronSymbols.archive)
        }
        .disabled(!availability.canArchive)
        .keyboardShortcut(shortcut("a", modifiers: [.command, .option]))
    }

    @ViewBuilder
    private func sectionChoices(_ id: UUID) -> some View {
        let currentFolderID = model.sidebarState.sidebarOrganization.folderID(for: .conversation(id))
        Button { model.moveChatToSection(id, folderID: nil) } label: {
            if currentFolderID == nil {
                Label(VyronSidebarText.topLevel, systemImage: VyronSymbols.check)
            } else {
                Text(VyronSidebarText.topLevel)
            }
        }
        if !model.chatSectionFolders.isEmpty { Divider() }
        ForEach(model.chatSectionFolders) { folder in
            Button { model.moveChatToSection(id, folderID: folder.id) } label: {
                if currentFolderID == folder.id {
                    Label(model.chatSectionName(folder.id), systemImage: VyronSymbols.check)
                } else {
                    Text(verbatim: model.chatSectionName(folder.id))
                }
            }
        }
    }

    private func shortcut(_ key: KeyEquivalent, modifiers: EventModifiers) -> KeyboardShortcut? {
        usesKeyboardShortcuts ? KeyboardShortcut(key, modifiers: modifiers) : nil
    }

    private func copy(_ text: String?) {
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
