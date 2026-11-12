import SwiftUI

struct VyronComposerProjectMenu: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let _ = localizationLocale
        Menu {
            if let projectPath = model.sidebarActiveProjectPath {
                Text(VyronSidebarText.sourceFolders)
                ForEach(model.sidebarProjectSourceFolders(projectPath), id: \.self) { path in
                    Button {
                        model.openSidebarProjectSourceFolder(path, projectPath: projectPath)
                    } label: {
                        if model.workspaceState.workspaceURL?.standardizedFileURL.path == path {
                            Label(folderLabel(path), systemImage: VyronSymbols.check)
                        } else {
                            Text(verbatim: folderLabel(path))
                        }
                    }
                    .disabled(!model.canEditSidebarProjectFolders(projectPath))
                }
                Divider()
            }
            Button(VyronWorkspaceText.openProject) { model.chooseWorkspace() }
        } label: {
            Label {
                Text(verbatim: label)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: VyronSymbols.folder)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(Palette.text)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: VyronWorkspaceStyle.projectLabelWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .help(model.workspaceState.workspaceURL?.path ?? VyronSidebarText.selectSourceFolder)
        .accessibilityLabel(VyronSidebarText.selectSourceFolder)
    }

    private var label: String {
        guard let projectPath = model.sidebarActiveProjectPath else { return VyronWorkspaceText.openProject }
        let name = model.sidebarProjectName(projectPath)
        guard model.sidebarProjectSourceFolders(projectPath).count > 1,
            let source = model.workspaceState.workspaceURL
        else {
            return name
        }
        return name + " · " + source.lastPathComponent
    }

    private func folderLabel(_ path: String) -> String {
        let folder = URL(fileURLWithPath: path).lastPathComponent
        guard let project = model.sidebarActiveProjectPath else { return folder }
        let sameNames = model.sidebarProjectSourceFolders(project).filter {
            URL(fileURLWithPath: $0).lastPathComponent == folder
        }
        return sameNames.count > 1 ? NSString(string: path).abbreviatingWithTildeInPath : folder
    }
}
