import SwiftUI
import VyronCore

extension ProjectSidebar {
    @ViewBuilder
    func entryView(_ entry: VyronSidebarEntry) -> some View {
        switch entry.kind {
        case .section(let section):
            Text(section.title)
                .font(VyronSidebarStyle.sectionFont)
                .foregroundStyle(palette.muted)
                .padding(.horizontal, VyronSidebarStyle.rowInset)
                .padding(.top, VyronSidebarStyle.sectionSpacing)
                .padding(.bottom, VyronSidebarStyle.sectionBottomSpacing)
        case .folder(let folder):
            folderRow(folder)
        case .project(let project):
            projectRow(project)
        case .chat(let chat):
            chatRow(chat)
        case .hint(let hint):
            Text(hint.title)
                .font(VyronSidebarStyle.detailFont)
                .foregroundStyle(palette.muted)
                .padding(VyronSidebarStyle.rowInset)
        case .overflow(let overflow):
            Button {
                if overflow.showsAll {
                    expandedChatProjects.remove(overflow.projectPath)
                } else {
                    expandedChatProjects.insert(overflow.projectPath)
                }
            } label: {
                Text(overflow.showsAll ? VyronSidebarText.showLess : VyronSidebarText.showMore)
                    .font(VyronSidebarStyle.rowFont)
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, VyronSidebarStyle.rowInset)
                    .frame(maxWidth: .infinity, minHeight: VyronSidebarStyle.rowHeight, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(VyronSidebarRowBackground())
        }
    }

    private func folderRow(_ folder: SidebarFolder) -> some View {
        let expanded = isSearching || model.sidebarState.sidebarOrganization.isFolderExpanded(folder.id)
        return Button {
            guard !isSearching else { return }
            model.setSidebarFolderExpanded(folder.id, expanded: !expanded)
        } label: {
            HStack(spacing: VyronSidebarStyle.rowContentSpacing) {
                Image(systemName: expanded ? VyronSymbols.folderFilled : VyronSymbols.folder)
                    .foregroundStyle(palette.muted)
                    .frame(width: VyronSidebarStyle.rowIconWidth)
                Text(folder.name).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: expanded ? VyronSymbols.chevronDown : VyronSymbols.chevronRight)
                    .font(VyronSidebarStyle.disclosureFont)
                    .foregroundStyle(palette.muted)
            }
            .font(VyronSidebarStyle.rowFont)
            .padding(.horizontal, VyronSidebarStyle.rowInset)
            .frame(height: VyronSidebarStyle.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(VyronSidebarRowBackground())
        .help(isSearching ? VyronSidebarText.clearSearchToExpand : folderBreadcrumb(folder.id))
        .accessibilityValue(expanded ? VyronSidebarText.collapseFolder : VyronSidebarText.expandFolder)
        .contextMenu { folderMenu(folder) }
    }

    private func projectRow(_ project: VyronSidebarProject) -> some View {
        VyronSidebarProjectRow(
            path: project.path,
            detail: projectDisambiguation(project.path),
            isSearching: isSearching
        ) {
            projectMenu(project.path)
        }
    }

    private func chatRow(_ chat: VyronSidebarChat) -> some View {
        let conversation = chat.conversation
        let selected = model.selectedConversationID == conversation.id
        let working = model.isSidebarConversationActive(conversation.id)
        return Button {
            model.requestSidebarConversation(conversation.id)
        } label: {
            HStack(spacing: VyronSidebarStyle.rowContentSpacing) {
                if chat.showsProject {
                    Image(systemName: VyronSymbols.chat)
                        .foregroundStyle(palette.muted)
                        .frame(width: VyronSidebarStyle.rowIconWidth)
                }
                VStack(alignment: .leading, spacing: VyronSidebarStyle.rowSpacing) {
                    Text(conversation.title).lineLimit(1).truncationMode(.tail)
                    if chat.showsProject, let path = conversation.sidebarProjectPath {
                        Text(projectName(path) + (projectDisambiguation(path).map { " · " + $0 } ?? ""))
                            .font(VyronSidebarStyle.captionFont)
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if conversation.isUnread == true {
                    Image(systemName: VyronSymbols.unread)
                        .resizable()
                        .frame(width: VyronSidebarStyle.statusSize, height: VyronSidebarStyle.statusSize)
                        .foregroundStyle(palette.text)
                        .help(VyronHeaderText.unread)
                        .accessibilityLabel(VyronHeaderText.unread)
                }
                if working {
                    ProgressView().controlSize(.mini)
                        .accessibilityLabel(VyronWorkspaceText.working)
                } else if chat.hasFailedResponse {
                    Image(systemName: VyronSymbols.warning)
                        .font(VyronSidebarStyle.iconFont)
                        .foregroundStyle(palette.danger)
                        .help(VyronStatusText.responseFailed)
                        .accessibilityLabel(VyronStatusText.responseFailed)
                } else if chat.isPinned {
                    Image(systemName: VyronSymbols.pinFilled)
                        .font(VyronSidebarStyle.pinFont)
                        .foregroundStyle(palette.muted)
                }
            }
            .font(VyronSidebarStyle.rowFont)
            .padding(.horizontal, VyronSidebarStyle.rowInset)
            .frame(maxWidth: .infinity, minHeight: VyronSidebarStyle.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(VyronSidebarRowBackground(isSelected: selected))
        .help(conversation.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu { itemMenu(.conversation(conversation.id)) }
    }
}
