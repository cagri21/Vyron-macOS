import SwiftUI
import VyronCore

extension ProjectSidebar {
    @ViewBuilder
    func folderMenu(_ folder: SidebarFolder) -> some View {
        Button(VyronSidebarText.newSubfolder) { requestNewFolder(parentID: folder.id) }
        Button(VyronSidebarText.renameFolder) {
            nameRequest = VyronSidebarNameRequest(
                operation: .renameFolder,
                targetID: folder.id,
                title: VyronSidebarText.renameFolderTitle,
                initialValue: folder.name
            )
        }
        Menu(VyronSidebarText.moveTo) {
            Button {
                _ = model.moveSidebarFolder(folder.id, toParent: nil)
            } label: {
                if folder.parentID == nil {
                    Label(VyronSidebarText.topLevel, systemImage: VyronSymbols.check)
                } else {
                    Text(VyronSidebarText.topLevel)
                }
            }
            ForEach(sortedMoveTargets(excluding: folder.id)) { target in
                Button {
                    _ = model.moveSidebarFolder(folder.id, toParent: target.id)
                } label: {
                    if folder.parentID == target.id {
                        Label(folderBreadcrumb(target.id), systemImage: VyronSymbols.check)
                    } else {
                        Text(folderBreadcrumb(target.id))
                    }
                }
            }
        }
        Divider()
        Button(VyronSidebarText.removeFolder, role: .destructive) { _ = model.removeSidebarFolder(folder.id) }
    }

    @ViewBuilder
    func itemMenu(_ item: SidebarItem) -> some View {
        if case .project(let path) = item {
            projectMenu(path)
        } else {
            chatMenu(item)
        }
    }

    @ViewBuilder
    func projectMenu(_ path: String) -> some View {
        let item = SidebarItem.project(path)
        Button {
            model.toggleSidebarPin(item)
        } label: {
            Label(
                model.sidebarState.sidebarOrganization.isPinned(item) ? VyronSidebarText.unpin : VyronSidebarText.pin,
                systemImage: model.sidebarState.sidebarOrganization.isPinned(item)
                    ? VyronSymbols.unpin : VyronSymbols.pin
            )
        }
        Button {
            editingProject = VyronSidebarProjectSelection(path: path)
        } label: {
            Label(VyronSidebarText.edit, systemImage: VyronSymbols.settings)
        }
        Divider()
        Menu {
            placementMenu(item)
        } label: {
            Label(VyronSidebarText.section, systemImage: VyronSymbols.section)
        }
        Button {
            model.revealSidebarProject(path)
        } label: {
            Label(VyronSidebarText.revealInFinder, systemImage: VyronSymbols.folder)
        }
        Divider()
        Button {
            _ = model.archiveSidebarProject(path)
        } label: {
            Label(VyronSidebarText.archiveChats, systemImage: VyronSymbols.archive)
        }
        .disabled(!model.canArchiveSidebarProject(path))
        Divider()
        Button(role: .destructive) {
            _ = model.removeSidebarProject(path)
        } label: {
            Label(VyronSidebarText.removeProject, systemImage: VyronSymbols.close)
        }
        .disabled(!model.canRemoveSidebarProject(path))
    }

    @ViewBuilder
    private func chatMenu(_ item: SidebarItem) -> some View {
        if case .conversation(let id) = item, let availability = model.chatActions(for: id) {
            VyronChatMenuActions(
                availability: availability,
                usesKeyboardShortcuts: false,
                rename: { selection in
                    nameRequest = VyronSidebarNameRequest(
                        operation: .renameChat,
                        targetID: selection.conversationID,
                        title: VyronHeaderText.renameTitle,
                        initialValue: selection.title
                    )
                },
                schedule: { chatSchedulingTemplate = $0 }
            )
            Divider()
            Button(VyronSidebarText.deleteChat, role: .destructive) { model.deleteConversation(id) }
                .disabled(model.foregroundRun.response(in: id) != nil)
        }
    }

    @ViewBuilder
    private func placementMenu(_ item: SidebarItem) -> some View {
        Button {
            _ = model.moveSidebarItem(item, toFolder: nil)
        } label: {
            if model.sidebarState.sidebarOrganization.folderID(for: item) == nil {
                Label(VyronSidebarText.topLevel, systemImage: VyronSymbols.check)
            } else {
                Text(VyronSidebarText.topLevel)
            }
        }
        if !model.sidebarState.sidebarOrganization.folders.isEmpty { Divider() }
        ForEach(
            model.sidebarState.sidebarOrganization.folders.sorted {
                folderBreadcrumb($0.id).localizedStandardCompare(folderBreadcrumb($1.id)) == .orderedAscending
            }
        ) { folder in
            Button {
                _ = model.moveSidebarItem(item, toFolder: folder.id)
            } label: {
                if model.sidebarState.sidebarOrganization.folderID(for: item) == folder.id {
                    Label(folderBreadcrumb(folder.id), systemImage: VyronSymbols.check)
                } else {
                    Text(folderBreadcrumb(folder.id))
                }
            }
        }
    }

    func requestNewFolder(parentID: UUID?) {
        nameRequest = VyronSidebarNameRequest(
            operation: .newFolder,
            targetID: parentID,
            title: parentID == nil ? VyronSidebarText.folderNameTitle : VyronSidebarText.subfolderNameTitle,
            initialValue: ""
        )
    }

    func saveName(_ name: String, request: VyronSidebarNameRequest) -> String? {
        let saved: Bool
        switch request.operation {
        case .newFolder:
            saved = model.createSidebarFolder(name: name, parentID: request.targetID) != nil
            if saved {
                model.sidebarState.sidebarSearchText = ""
                if let parentID = request.targetID { model.setSidebarFolderExpanded(parentID, expanded: true) }
            }
        case .renameFolder:
            guard let id = request.targetID else { return VyronSidebarText.saveFailure }
            saved = model.renameSidebarFolder(id, name: name)
        case .renameChat:
            guard let id = request.targetID else { return VyronSidebarText.saveFailure }
            saved = model.renameChat(id, title: name)
        }
        return saved ? nil : (model.errorMessage ?? VyronSidebarText.saveFailure)
    }
}
