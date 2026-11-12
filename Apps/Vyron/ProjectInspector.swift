import AppKit
import SwiftUI
import VyronCore
import VyronDevelopment

struct ProjectInspector: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let _ = localizationLocale
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker(
                    VyronAppText.inspectorTitle,
                    selection: Binding(
                        get: { model.inspector.inspectorTab },
                        set: { model.inspector.inspectorTab = $0 }
                    )
                ) {
                    ForEach(ProjectInspectorTab.allCases, id: \.self) { tab in
                        Text(
                            tab == .changes && !model.inspector.developmentChanges.isEmpty
                                ? VyronAppText.inspectorChangesCount(model.inspector.developmentChanges.count)
                                : inspectorTabLabel(tab)
                        ).tag(tab)
                    }
                }.pickerStyle(.segmented).controlSize(.small)
                Button {
                    model.refreshProject()
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }
                .buttonStyle(.plain).foregroundStyle(Palette.muted).help(VyronAppText.inspectorRefresh)
            }.padding(13)
            Rectangle().fill(Palette.border).frame(height: 1)
            if model.workspaceState.workspaceURL == nil {
                VStack(spacing: 12) {
                    Image(systemName: "folder").font(.system(size: 25, weight: .ultraLight)).foregroundStyle(
                        Palette.muted
                    )
                    Text(VyronAppText.inspectorOpenHint)
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    Button(VyronAppText.inspectorOpenProject) { model.chooseWorkspace() }
                        .buttonStyle(AccentButtonStyle())
                }.padding(25).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch model.inspector.inspectorTab {
                case .files: ProjectFilesView()
                case .changes: ProjectChangesView()
                case .activity: ProjectActivityView()
                }
            }
        }.background(Palette.sidebar.opacity(0.65))
    }
}

private func inspectorTabLabel(_ tab: ProjectInspectorTab) -> String {
    switch tab {
    case .files: VyronAppText.inspectorFiles
    case .changes: VyronAppText.inspectorChanges
    case .activity: VyronAppText.inspectorActivity
    }
}

private struct ProjectFilesView: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: 0) {
            if let path = model.inspector.selectedProjectFilePath {
                HStack(spacing: 7) {
                    Button {
                        model.inspector.selectedProjectFilePath = nil; model.inspector.projectFilePreview = ""
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 10))
                    }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                    Text(path).font(.system(size: 10, weight: .medium, design: .monospaced)).lineLimit(2)
                    Spacer(minLength: 0)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.inspector.projectFilePreview, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 10))
                    }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted).help(VyronAppText.inspectorCopyPreview)
                }.padding(13)
                Rectangle().fill(Palette.border).frame(height: 1)
                ScrollView([.horizontal, .vertical]) {
                    Text(model.inspector.projectFilePreview)
                        .font(.system(size: 10, design: .monospaced)).lineSpacing(4)
                        .textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .topLeading).padding(14)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Text(VyronAppText.inspectorReadOnlyPreview)
                    .font(.system(size: 9)).foregroundStyle(Palette.muted).padding(12)
            } else {
                TextField(
                    VyronAppText.inspectorFindFile,
                    text: Binding(
                        get: { model.workspaceState.searchText },
                        set: { model.workspaceState.searchText = $0 }
                    )
                )
                    .textFieldStyle(.roundedBorder).font(.system(size: 11)).padding(12)
                HStack {
                    Text(model.workspaceState.workspaceURL?.lastPathComponent ?? VyronAppText.inspectorProject)
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                    Text(VyronAppText.inspectorFilesCount(model.inspector.developmentFiles.count))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                }.padding(.horizontal, 15).padding(.bottom, 8)
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(
                            model.inspector.filteredDevelopmentFiles(matching: model.workspaceState.searchText)
                        ) { file in
                            Button {
                                model.openProjectFile(file)
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: fileIcon(file.name)).font(.system(size: 11)).foregroundStyle(
                                        Palette.muted
                                    ).frame(width: 14).padding(.top, 1)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(file.name).font(.system(size: 11)).lineLimit(1)
                                        if file.path != file.name {
                                            Text(file.path).font(.system(size: 8, design: .monospaced)).foregroundStyle(
                                                Palette.muted
                                            ).lineLimit(1).truncationMode(.middle)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }.padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical, 2)
                }
                Text(VyronAppText.inspectorFilesHint)
                    .font(.system(size: 9)).foregroundStyle(Palette.muted).lineSpacing(3).padding(14)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func fileIcon(_ name: String) -> String {
        if name.hasSuffix(".swift") { return "swift" }
        if [".json", ".yaml", ".yml", ".toml"].contains(where: name.hasSuffix) { return "curlybraces" }
        if name.hasSuffix(".md") { return "doc.text" }
        return "chevron.left.forwardslash.chevron.right"
    }
}

private struct ProjectChangesView: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @State private var diffMode = "Diff"

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: 0) {
            if let change = model.inspector.selectedDevelopmentChange {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(
                        VyronAppText.inspectorChangedFile,
                        selection: Binding(
                            get: { model.inspector.selectedDevelopmentChange?.path ?? "" },
                            set: { model.inspector.selectedChangePath = $0 }
                        )
                    ) {
                        ForEach(model.inspector.developmentChanges) { item in Text(item.path).tag(item.path) }
                    }.font(.system(size: 10, design: .monospaced)).labelsHidden()
                    HStack {
                        Label(
                            change.before == nil ? VyronAppText.inspectorAddedFile : VyronAppText.inspectorModifiedFile,
                            systemImage: change.before == nil ? "plus.circle" : "pencil.circle"
                        )
                        .font(.system(size: 9)).foregroundStyle(Palette.accent)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(change.unifiedDiff, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc").font(.system(size: 10))
                        }
                        .buttonStyle(.plain).foregroundStyle(Palette.muted).help(VyronAppText.inspectorCopyDiff)
                        Button(VyronAppText.inspectorRevert) { model.revertChange(change.path) }
                            .font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(Palette.warning).disabled(
                                model.foregroundRun.isGenerating || model.foregroundRun.isStoppingDevelopment
                            )
                    }
                    Picker(VyronAppText.inspectorView, selection: $diffMode) {
                        Text(VyronAppText.inspectorDiff).tag("Diff")
                        Text(VyronAppText.inspectorBefore).tag("Before")
                        Text(VyronAppText.inspectorAfter).tag("After")
                    }.pickerStyle(.segmented).controlSize(.small)
                }.padding(13)
                Rectangle().fill(Palette.border).frame(height: 1)
                ScrollView([.horizontal, .vertical]) {
                    if diffMode == "Diff" {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(change.unifiedDiff.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                                Text(line.isEmpty ? " " : line)
                                    .foregroundStyle(diffColor(line)).padding(.vertical, 2)
                            }
                        }
                        .font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false).padding(13)
                    } else {
                        Text(
                            diffMode == "Before"
                                ? (change.before ?? VyronAppText.inspectorFileDidNotExist) : change.after
                        )
                        .font(.system(size: 10, design: .monospaced)).lineSpacing(4).textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false).padding(13)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Text(
                    VyronAppText.inspectorChangesHint
                )
                .font(.system(size: 9)).foregroundStyle(Palette.muted).lineSpacing(3).padding(13)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 24, weight: .ultraLight))
                        .foregroundStyle(Palette.muted)
                    Text(VyronAppText.inspectorNoChanges).font(.system(size: 12, weight: .medium))
                    Text(VyronAppText.inspectorCompletedEditsHint)
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                        .lineSpacing(4)
                }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func diffColor(_ line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return Palette.muted }
        if line.hasPrefix("+") { return Palette.diffAdded }
        if line.hasPrefix("-") { return Palette.diffRemoved }
        if line.hasPrefix("@@") { return Palette.diffHunk }
        return Palette.text.opacity(0.85)
    }
}

private struct ProjectActivityView: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    var body: some View {
        let _ = localizationLocale
        ScrollView {
            if model.inspector.developmentEvents.isEmpty {
                VStack(spacing: 11) {
                    Image(systemName: "list.bullet.rectangle").font(.system(size: 24, weight: .ultraLight))
                        .foregroundStyle(Palette.muted)
                    Text(VyronAppText.inspectorActivityHint).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity).padding(.top, 60)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.inspector.developmentEvents.filter { $0.kind != .commandOutput }) { event in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: icon(event.kind)).font(.system(size: 10)).foregroundStyle(
                                Palette.accent.opacity(0.85)
                            ).frame(width: 14).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(event.localizedMessage).font(.system(size: 10)).lineSpacing(4).textSelection(.enabled)
                                if let path = event.path {
                                    Text(path).font(.system(size: 8, design: .monospaced)).foregroundStyle(
                                        Palette.muted
                                    ).lineLimit(2)
                                }
                                if let command = event.command {
                                    Text(command).font(.system(size: 9, design: .monospaced)).foregroundStyle(
                                        Palette.muted
                                    ).lineLimit(3).textSelection(.enabled)
                                }
                            }
                            Spacer(minLength: 0)
                        }.padding(.vertical, 13)
                        Rectangle().fill(Palette.border).frame(height: 1)
                    }
                }.padding(.horizontal, 14)
            }
        }
    }

    private func icon(_ kind: DevelopmentEvent.Kind) -> String {
        switch kind {
        case .fileChanged: return "pencil"
        case .commandStarted, .commandOutput, .commandFinished: return "terminal"
        case .toolStarted: return "magnifyingglass"
        case .toolFinished: return "checkmark"
        case .assistant: return "bubble.left"
        case .status: return "circle.dotted"
        }
    }
}

struct DevelopmentTerminal: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    var body: some View {
        let _ = localizationLocale
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "terminal").font(.system(size: 11)).foregroundStyle(Palette.accent)
                Text(VyronAppText.inspectorTerminal).font(.system(size: 11, weight: .medium))
                Text(VyronAppText.inspectorCommandOutput).font(.system(size: 9)).foregroundStyle(Palette.muted)
                Spacer()
                Button(VyronAppText.inspectorClear) { model.inspector.terminalOutput = "" }
                    .font(.system(size: 9)).buttonStyle(.plain)
                    .foregroundStyle(Palette.muted)
                Button {
                    model.inspector.showTerminal = false
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9))
                }
                .buttonStyle(.plain).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 16).padding(.vertical, 11)
            Rectangle().fill(Palette.border).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(
                            model.inspector.terminalOutput.isEmpty
                                ? VyronAppText.inspectorTerminalHint : model.inspector.terminalOutput
                        )
                        .font(.system(size: 10, design: .monospaced)).lineSpacing(3)
                        .foregroundStyle(
                            model.inspector.terminalOutput.isEmpty ? Palette.muted : Palette.text.opacity(0.9)
                        )
                        .textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
                        Color.clear.frame(height: 1).id("terminal-bottom")
                    }.padding(14).frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .onChange(of: model.inspector.terminalOutput) { _, _ in
                    proxy.scrollTo("terminal-bottom", anchor: .bottomLeading)
                }
            }
        }.background(Palette.terminal)
    }
}
