import SwiftUI

struct VyronSidebarProjectEditor: View {
    @Environment(\.locale) private var localizationLocale
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var name = ""
    @State private var sourceFolders: [String] = []
    @State private var originalSourceFolders: [String] = []
    @State private var error: String?
    @State private var hasLoadedProject = false
    @State private var isSaving = false
    @FocusState private var nameFocused: Bool
    let projectPath: String

    private var canEditFolders: Bool { model.canEditSidebarProjectFolders(projectPath) && !isSaving }
    private var foldersChanged: Bool { sourceFolders != originalSourceFolders }
    private var canSave: Bool {
        !isSaving && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sourceFolders.isEmpty && (!foldersChanged || canEditFolders)
    }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronSidebarStyle.projectEditorSpacing) {
            header
            HStack(spacing: VyronSidebarStyle.projectEditorFieldSpacing) {
                Image(systemName: VyronSymbols.folder)
                    .foregroundStyle(Palette.muted)
                TextField(VyronSidebarText.projectName, text: $name)
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .onSubmit(save)
                    .accessibilityLabel(VyronSidebarText.projectName)
            }
            .font(VyronSidebarStyle.projectEditorNameFont)
            .padding(.horizontal, VyronSidebarStyle.projectEditorFieldPadding)
            .frame(height: VyronSidebarStyle.projectEditorFieldHeight)
            .background(Palette.field, in: RoundedRectangle(cornerRadius: VyronSidebarStyle.rowRadius))
            .overlay {
                RoundedRectangle(cornerRadius: VyronSidebarStyle.rowRadius)
                    .stroke(
                        nameFocused ? Palette.controlAccent : Palette.border,
                        lineWidth: VyronSidebarStyle.projectEditorBorderWidth
                    )
                    .allowsHitTesting(false)
            }
            sourceFolderSection
            if let error {
                Text(verbatim: error)
                    .font(VyronSidebarStyle.detailFont)
                    .foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            actions
        }
        .padding(VyronSidebarStyle.editorPadding)
        .frame(width: VyronSidebarStyle.projectEditorWidth)
        .background(Palette.canvas)
        .foregroundStyle(Palette.text)
        .tint(Palette.controlAccent)
        .onAppear {
            if !hasLoadedProject {
                name = model.sidebarProjectName(projectPath)
                sourceFolders = uniqueFolders(model.sidebarProjectSourceFolders(projectPath))
                originalSourceFolders = sourceFolders
                hasLoadedProject = true
            }
            nameFocused = true
        }
        .onChange(of: name) { _, _ in error = nil }
        .onChange(of: sourceFolders) { _, _ in error = nil }
    }

    private var header: some View {
        HStack {
            Text(VyronSidebarText.editProject)
                .font(VyronSidebarStyle.projectEditorTitleFont)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: VyronSymbols.close)
                    .font(VyronSidebarStyle.iconFont)
                    .foregroundStyle(Palette.muted)
                    .frame(
                        width: VyronSidebarStyle.projectEditorCloseSize,
                        height: VyronSidebarStyle.projectEditorCloseSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(VyronSidebarText.closeProjectEditor)
            .accessibilityLabel(VyronSidebarText.closeProjectEditor)
        }
    }

    private var sourceFolderSection: some View {
        VStack(alignment: .leading, spacing: VyronSidebarStyle.projectEditorFolderSpacing) {
            Text(VyronSidebarText.sourceFolders)
                .font(VyronSidebarStyle.projectEditorSectionFont)
            VStack(spacing: 0) {
                if !sourceFolders.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(sourceFolders, id: \.self) { path in
                                sourceFolderRow(path)
                                Rectangle()
                                    .fill(Palette.border)
                                    .frame(height: VyronSidebarStyle.projectEditorBorderWidth)
                            }
                        }
                    }
                    .frame(height: sourceFolderListHeight)
                }
                Button(action: addFolders) {
                    Label(VyronSidebarText.addFolder, systemImage: VyronSymbols.folderAdd)
                        .font(VyronSidebarStyle.rowFont)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, VyronSidebarStyle.projectEditorFieldPadding)
                        .frame(height: VyronSidebarStyle.projectEditorFolderRowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(canEditFolders ? Palette.text : Palette.muted)
                .disabled(!canEditFolders)
            }
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: VyronSidebarStyle.rowRadius))
            .overlay {
                RoundedRectangle(cornerRadius: VyronSidebarStyle.rowRadius)
                    .stroke(Palette.border, lineWidth: VyronSidebarStyle.projectEditorBorderWidth)
                    .allowsHitTesting(false)
            }
            if sourceFolders.isEmpty {
                Text(VyronSidebarText.sourceFolderRequired)
                    .font(VyronSidebarStyle.detailFont)
                    .foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.canEditSidebarProjectFolders(projectPath) {
                Text(VyronSidebarText.sourceFoldersBusy)
                    .font(VyronSidebarStyle.detailFont)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sourceFolderListHeight: CGFloat {
        let rowCount = CGFloat(sourceFolders.count)
        return min(
            VyronSidebarStyle.projectEditorFolderListHeight,
            rowCount * (VyronSidebarStyle.projectEditorFolderRowHeight + VyronSidebarStyle.projectEditorBorderWidth)
        )
    }

    private func sourceFolderRow(_ path: String) -> some View {
        HStack(spacing: VyronSidebarStyle.projectEditorFieldSpacing) {
            Image(systemName: VyronSymbols.folder)
                .foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: VyronSidebarStyle.rowSpacing) {
                Text(verbatim: URL(fileURLWithPath: path).lastPathComponent)
                    .font(VyronSidebarStyle.rowFont)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: (path as NSString).abbreviatingWithTildeInPath)
                    .font(VyronSidebarStyle.detailFont)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(path)
            Button {
                sourceFolders.removeAll { $0 == path }
            } label: {
                Image(systemName: VyronSymbols.close)
                    .font(VyronSidebarStyle.iconFont)
                    .foregroundStyle(Palette.muted)
                    .frame(
                        width: VyronSidebarStyle.projectEditorCloseSize,
                        height: VyronSidebarStyle.projectEditorCloseSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canEditFolders)
            .help(VyronSidebarText.removeSourceFolder)
            .accessibilityLabel(VyronSidebarText.removeSourceFolder + ": " + path)
        }
        .padding(.horizontal, VyronSidebarStyle.projectEditorFieldPadding)
        .frame(height: VyronSidebarStyle.projectEditorFolderRowHeight)
    }

    private var actions: some View {
        HStack(spacing: VyronSidebarStyle.rowContentSpacing) {
            Button(role: .destructive, action: removeProject) {
                Text(VyronSidebarText.removeLocalProject)
                    .font(VyronSidebarStyle.detailFont)
                    .foregroundStyle(Palette.danger)
                    .padding(.horizontal, VyronSidebarStyle.projectEditorButtonInset)
                    .frame(height: VyronSidebarStyle.projectEditorButtonHeight)
                    .background(
                        Palette.danger.opacity(VyronSidebarStyle.projectEditorDestructiveOpacity),
                        in: RoundedRectangle(cornerRadius: VyronSidebarStyle.rowRadius)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isSaving || !model.canRemoveSidebarProject(projectPath))
            .opacity(
                model.canRemoveSidebarProject(projectPath)
                    ? 1 : VyronSidebarStyle.projectEditorDisabledOpacity
            )
            Spacer(minLength: VyronSidebarStyle.projectEditorActionSpacing)
            Button(VyronSidebarText.cancel, role: .cancel) { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
            Button(VyronSidebarText.save, action: save)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Palette.text)
                .foregroundStyle(Palette.canvas)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
    }

    private func addFolders() {
        guard canEditFolders else { return }
        let selectedFolders = model.chooseSidebarProjectSourceFolders()
        guard canEditFolders else { return }
        sourceFolders = uniqueFolders(sourceFolders + selectedFolders)
    }

    private func uniqueFolders(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.compactMap { path in
            let normalized = URL(fileURLWithPath: path, isDirectory: true)
                .standardizedFileURL.path
            return seen.insert(normalized).inserted ? normalized : nil
        }
    }

    private func removeProject() {
        guard !isSaving else { return }
        if model.removeSidebarProject(projectPath) {
            dismiss()
        } else {
            error = model.errorMessage ?? VyronSidebarText.removeProjectUnavailable
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        if model.saveSidebarProject(projectPath, name: name, sourceFolders: sourceFolders) {
            dismiss()
        } else {
            error = model.errorMessage ?? VyronSidebarText.saveFailure
            isSaving = false
        }
    }
}
