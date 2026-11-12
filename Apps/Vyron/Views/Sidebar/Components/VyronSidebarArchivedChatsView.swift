import SwiftUI

struct VyronSidebarArchivedChatsView: View {
    @Environment(\.locale) private var localizationLocale
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var error: String?

    private var matchingConversations: [Conversation] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.archivedSidebarConversations }
        return model.archivedSidebarConversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(query)
                || conversation.sidebarProjectPath.map {
                    model.sidebarProjectName($0).localizedCaseInsensitiveContains(query)
                        || $0.localizedCaseInsensitiveContains(query)
                } == true
        }
    }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronSidebarStyle.headerInset) {
            HStack {
                Text(VyronSidebarText.archivedChats)
                    .font(VyronSidebarStyle.editorTitleFont)
                Spacer()
                Button(VyronSidebarText.done) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            Text(VyronSidebarText.archivedChatsHint)
                .font(VyronSidebarStyle.detailFont)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: VyronSidebarStyle.rowContentSpacing) {
                Image(systemName: VyronSymbols.search)
                    .foregroundStyle(Palette.muted)
                TextField(VyronSidebarText.searchArchivedChats, text: $search)
                    .textFieldStyle(.plain)
                    .accessibilityLabel(VyronSidebarText.searchArchivedChats)
            }
            .font(VyronSidebarStyle.rowFont)
            .padding(VyronSidebarStyle.rowInset)
            .background(Palette.field, in: RoundedRectangle(cornerRadius: VyronSidebarStyle.rowRadius))
            if let error {
                Text(verbatim: error)
                    .font(VyronSidebarStyle.detailFont)
                    .foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if matchingConversations.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: VyronSidebarStyle.controlSpacing) {
                        ForEach(matchingConversations) { conversation in
                            chatRow(conversation)
                        }
                    }
                }
            }
        }
        .padding(VyronSidebarStyle.editorPadding)
        .frame(width: VyronSidebarStyle.archiveSheetWidth, height: VyronSidebarStyle.archiveSheetHeight)
        .background(Palette.canvas)
        .foregroundStyle(Palette.text)
        .tint(Palette.controlAccent)
    }

    private var emptyState: some View {
        VStack(spacing: VyronSidebarStyle.rowContentSpacing) {
            Image(systemName: VyronSymbols.archive)
                .font(VyronSidebarStyle.archiveEmptyIconFont)
            Text(
                model.archivedSidebarConversations.isEmpty
                    ? VyronSidebarText.noArchivedChats : VyronSidebarText.noMatchingArchivedChats
            )
            .font(VyronSidebarStyle.rowFont)
            .multilineTextAlignment(.center)
        }
        .foregroundStyle(Palette.muted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chatRow(_ conversation: Conversation) -> some View {
        VStack(alignment: .leading, spacing: VyronSidebarStyle.rowContentSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: VyronSidebarStyle.rowContentSpacing) {
                Text(verbatim: conversation.title)
                    .font(VyronSidebarStyle.rowFont)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(conversation.updatedAt, format: .dateTime.month(.abbreviated).day())
                    .font(VyronSidebarStyle.detailFont)
                    .foregroundStyle(Palette.muted)
            }
            if let path = conversation.sidebarProjectPath {
                Label {
                    Text(verbatim: model.sidebarProjectName(path))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: VyronSymbols.folder)
                }
                .font(VyronSidebarStyle.detailFont)
                .foregroundStyle(Palette.muted)
                .help(path)
            }
            HStack(spacing: VyronSidebarStyle.rowContentSpacing) {
                Spacer()
                Button(VyronSidebarText.restoreChat) { restore(conversation, open: false) }
                Button(VyronSidebarText.restoreAndOpen) { restore(conversation, open: true) }
            }
            .font(VyronSidebarStyle.detailFont)
        }
        .padding(VyronSidebarStyle.archiveRowPadding)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: VyronSidebarStyle.rowRadius))
    }

    private func restore(_ conversation: Conversation, open: Bool) {
        guard model.restoreSidebarConversation(conversation.id) else {
            error = model.errorMessage ?? VyronSidebarText.restoreFailure
            return
        }
        error = nil
        if open {
            model.requestSidebarConversation(conversation.id)
            dismiss()
        }
    }
}
