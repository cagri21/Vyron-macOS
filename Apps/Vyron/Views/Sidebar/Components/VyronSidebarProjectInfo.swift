import SwiftUI
import VyronCore

struct VyronSidebarProjectInfo: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    let path: String
    let onEdit: () -> Void

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronSidebarStyle.controlSpacing) {
            HStack(spacing: VyronSidebarStyle.rowContentSpacing) {
                Image(systemName: VyronSymbols.folder)
                Text(verbatim: model.sidebarProjectName(path)).lineLimit(1)
                Spacer(minLength: 0)
                if model.sidebarState.sidebarOrganization.isPinned(.project(path)) {
                    Image(systemName: VyronSymbols.pinFilled).foregroundStyle(Palette.muted)
                        .accessibilityLabel(VyronSidebarText.pin)
                }
            }
            Label {
                Text(
                    VyronSidebarText.projectChatCount(model.sidebarProjectConversations(path).count)
                        + " · " + VyronSidebarText.projectActiveCount(model.sidebarProjectActiveChatCount(path))
                )
            } icon: {
                Image(systemName: VyronSymbols.chat).foregroundStyle(Palette.muted)
            }
            Divider()
            sourceFolders
            Divider()
            Button(action: onEdit) {
                Label(VyronSidebarText.editProject, systemImage: VyronSymbols.settings)
            }
        }
        .font(VyronSidebarStyle.rowFont)
        .foregroundStyle(Palette.text)
        .buttonStyle(.plain)
        .padding(VyronSidebarStyle.projectInfoPadding)
        .frame(width: VyronSidebarStyle.projectInfoWidth, alignment: .leading)
        .background(Palette.raised)
    }

    private var sourceFolders: some View {
        let sources = model.sidebarProjectSourceFolders(path)
        return ScrollView {
            VStack(alignment: .leading, spacing: VyronSidebarStyle.controlSpacing) {
                ForEach(sources, id: \.self) { source in
                    Button {
                        model.revealSidebarProject(path)
                    } label: {
                        Label {
                            Text(verbatim: NSString(string: source).abbreviatingWithTildeInPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } icon: {
                            Image(systemName: VyronSymbols.folder).foregroundStyle(Palette.muted)
                        }
                    }
                    .help(source)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: min(CGFloat(sources.count) * VyronSidebarStyle.projectSourceInfoRowHeight,
            VyronSidebarStyle.projectSourcesInfoMaximumHeight))
    }
}
