import SwiftUI

struct VyronChatHandoffSheet: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @StateObject private var state: VyronChatHandoffState
    @State private var startsImmediately = true
    let presentation: VyronChatHandoffPresentation

    init(presentation: VyronChatHandoffPresentation) {
        self.presentation = presentation
        _state = StateObject(wrappedValue: VyronChatHandoffState(presentation: presentation))
    }

    private var projects: [String] {
        let sourceProject = model.conversations.first { $0.id == presentation.sourceID }?.sidebarProjectPath
        return model.chatHandoffProjects.filter { $0 != sourceProject }
    }

    private var folders: [String] { model.chatHandoffSourceFolders(for: state.selection.projectPath) }
    private var chats: [Conversation] { model.chatHandoffConversations(for: state.selection) }
    private var canSubmit: Bool {
        !state.isSaving && model.canPrepareChatHandoff(presentation)
            && projects.contains(state.selection.projectPath) && folders.contains(state.selection.workspacePath)
            && (state.selection.conversationID == nil || chats.contains { $0.id == state.selection.conversationID })
            && VyronChatHandoffContext.requestIsValid(state.request)
    }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronChatHandoffStyle.spacing) {
            Text(VyronHandoffText.title).font(VyronChatHandoffStyle.titleFont)
            Text(VyronHandoffText.explanation)
                .font(VyronChatHandoffStyle.bodyFont)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if projects.isEmpty {
                Text(VyronHandoffText.noProjects).foregroundStyle(palette.warning)
            } else {
                destinationFields
                requestField
                Toggle(VyronHandoffText.startNow, isOn: $startsImmediately)
                    .font(VyronChatHandoffStyle.bodyFont)
                Text(VyronHandoffText.contextLimit)
                    .font(VyronChatHandoffStyle.detailFont)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = state.error {
                Text(verbatim: error)
                    .font(VyronChatHandoffStyle.detailFont)
                    .foregroundStyle(palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.canPrepareChatHandoff(presentation), !state.isSaving {
                Text(VyronHandoffText.busy)
                    .font(VyronChatHandoffStyle.detailFont)
                    .foregroundStyle(palette.warning)
            }
            Divider()
            HStack {
                if state.isSaving {
                    ProgressView().controlSize(.small)
                    Text(VyronHandoffText.opening).font(VyronChatHandoffStyle.detailFont)
                }
                Spacer()
                Button(VyronHeaderText.cancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(state.isSaving)
                Button(startsImmediately ? VyronHandoffText.start : VyronHandoffText.prepare, action: submit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .padding(VyronChatHandoffStyle.padding)
        .frame(width: VyronChatHandoffStyle.width)
        .background(palette.canvas)
        .foregroundStyle(palette.text)
        .tint(palette.controlAccent)
        .interactiveDismissDisabled(state.isSaving)
        .onAppear(perform: initialize)
        .onChange(of: state.selection.projectPath) { _, _ in
            state.selection.workspacePath = folders.first ?? ""
            state.selection.conversationID = nil
            state.error = nil
        }
        .onChange(of: state.selection.workspacePath) { _, _ in
            state.selection.conversationID = nil
            state.error = nil
        }
        .onChange(of: state.selection.conversationID) { _, _ in state.error = nil }
    }

    private var destinationFields: some View {
        VStack(alignment: .leading, spacing: VyronChatHandoffStyle.spacing) {
            Picker(VyronHandoffText.project, selection: $state.selection.projectPath) {
                if !projects.contains(state.selection.projectPath) {
                    Text(state.selection.projectPath.isEmpty ? VyronHandoffText.project : VyronHandoffText.unavailable)
                        .tag(state.selection.projectPath)
                }
                ForEach(projects, id: \.self) { path in
                    Text(verbatim: model.sidebarProjectName(path) + " · "
                        + (path as NSString).abbreviatingWithTildeInPath).tag(path)
                }
            }
            if folders.count > 1 || !folders.contains(state.selection.workspacePath) {
                Picker(VyronHandoffText.sourceFolder, selection: $state.selection.workspacePath) {
                    if !folders.contains(state.selection.workspacePath) {
                        Text(VyronHandoffText.unavailable).tag(state.selection.workspacePath)
                    }
                    ForEach(folders, id: \.self) { path in
                        Text(verbatim: (path as NSString).abbreviatingWithTildeInPath).tag(path)
                    }
                }
            }
            Picker(VyronHandoffText.conversation, selection: $state.selection.conversationID) {
                Text(VyronHandoffText.newWorkChat).tag(Optional<UUID>.none)
                if let id = state.selection.conversationID, !chats.contains(where: { $0.id == id }) {
                    Text(VyronHandoffText.unavailable).tag(Optional(id))
                }
                ForEach(chats) { chat in Text(verbatim: chat.title).tag(Optional(chat.id)) }
            }
        }
        .font(VyronChatHandoffStyle.bodyFont)
        .disabled(state.isSaving)
    }

    private var requestField: some View {
        VStack(alignment: .leading, spacing: VyronChatHandoffStyle.fieldSpacing) {
            Text(VyronHandoffText.request).font(VyronChatHandoffStyle.labelFont)
            TextEditor(text: $state.request)
                .font(VyronChatHandoffStyle.bodyFont)
                .scrollContentBackground(.hidden)
                .padding(VyronChatHandoffStyle.requestPadding)
                .frame(height: VyronChatHandoffStyle.requestHeight)
                .background(palette.field, in: RoundedRectangle(cornerRadius: VyronChatHandoffStyle.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: VyronChatHandoffStyle.cornerRadius)
                        .stroke(palette.border, lineWidth: VyronChatHandoffStyle.borderWidth)
                }
                .accessibilityLabel(VyronHandoffText.request)
                .disabled(state.isSaving)
            if let failure = VyronChatHandoffContext.requestError(state.request) {
                Text(verbatim: failure)
                    .font(VyronChatHandoffStyle.detailFont)
                    .foregroundStyle(palette.danger)
            }
        }
    }

    private func initialize() {
        if state.request.isEmpty { state.request = model.chatHandoffDefaultRequest(for: presentation) }
        if presentation.destination != nil {
            if !projects.contains(state.selection.projectPath) || !folders.contains(state.selection.workspacePath)
                || (state.selection.conversationID != nil && !chats.contains {
                    $0.id == state.selection.conversationID
                }) {
                state.error = VyronHandoffText.unavailable
            }
            return
        }
        if presentation.requiresDestinationSelection { return }
        if !projects.contains(state.selection.projectPath) {
            state.selection = VyronChatHandoffSelection(projectPath: projects.first ?? "", workspacePath: "")
        }
        if !folders.contains(state.selection.workspacePath) {
            state.selection.workspacePath = folders.first ?? ""
        }
    }

    private func submit() {
        guard canSubmit else { return }
        state.isSaving = true
        state.error = nil
        let request = VyronChatHandoffRequest(
            source: presentation, destination: state.selection, prompt: state.request, startsImmediately: startsImmediately
        )
        Task { @MainActor in
            if await model.handOffChat(request) {
                let preparedID = model.selectedConversationID
                dismiss()
                if request.startsImmediately {
                    await Task.yield()
                    guard model.selectedConversationID == preparedID,
                        model.composer.draft == request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    else { return }
                    if model.canSend { model.send() }
                    else { model.statusMessage = VyronHandoffText.ready }
                }
            } else {
                state.error = model.errorMessage ?? VyronHandoffText.unavailable
                state.isSaving = false
            }
        }
    }
}
