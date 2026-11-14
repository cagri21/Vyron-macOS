import SwiftUI
import VyronCore

struct VyronComposer: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel

    private var isBusy: Bool { model.foregroundRun.isGenerating || model.computerWork.isComputerWorkActive }

    var body: some View {
        let _ = localizationLocale
        VStack(spacing: VyronWorkspaceStyle.compactSpacing) {
            if let error = model.workspaceError {
                errorNotice(error)
            }
            VyronVoiceStatusView(voice: model.voice)
            VyronQueuedMessagesView()
            VyronComposerSkillPicker(
                skills: model.composerSkills,
                draft: Binding(get: { model.composer.draft }, set: { model.composer.draft = $0 }),
                projectDirectory: model.workspaceState.workspaceURL,
                submit: {
                    if !model.composer.isEditingQueuedMessage { submit() }
                }
            )
            if let request = model.selectedUserInputRequest {
                VyronUserInputRequestView(request: request)
                    .id(request.id)
            }
            VStack(spacing: 0) {
                input
                if !model.isChatWorkspace { contextStrip }
            }
        }
        .frame(maxWidth: VyronWorkspaceStyle.contentWidth)
        .sheet(isPresented: Binding(
            get: { model.composerAttachments.showScreenshotPicker },
            set: { model.composerAttachments.showScreenshotPicker = $0 }
        )) {
            let generation = model.composerAttachments.screenshotCaptureGeneration
            VyronScreenshotPicker { data, name in
                model.completeScreenshotCapture(data, name: name, generation: generation)
            }
        }
    }

    private var input: some View {
        let draft = model.conversationDraftPrompt
        return VStack(alignment: .leading, spacing: VyronWorkspaceStyle.composerSpacing) {
            if model.sideChatCommand == nil, let filename = model.developmentTaskFilename(for: draft) {
                VyronDevelopmentTaskAttachmentView(filename: filename, content: draft)
            }
            if model.composerAttachments.hasDrafts { attachments }
            if model.composerAttachments.folderAttachmentDraft.isLoading {
                ProgressView(VyronFolderAttachmentText.importing)
                    .font(VyronWorkspaceStyle.captionFont)
            }
            if model.composerAttachments.screenshotDraft.isLoading {
                ProgressView(VyronScreenshotText.importing)
                    .font(VyronWorkspaceStyle.captionFont)
            }
            if model.composer.isEditingQueuedMessage {
                Text(VyronQueueText.editTitle)
                    .font(VyronFollowUpStyle.caption)
                    .foregroundStyle(palette.muted)
            }
            if model.isChatWorkspace {
                HStack(spacing: VyronWorkspaceStyle.controlSpacing) {
                    addMenu
                    composerInput
                        .layoutPriority(1)
                    VyronEffortControl()
                    voiceControls
                    if !showsLiveVoiceAction { VyronFollowUpActionsView(submit: submit) }
                }
            } else {
                composerInput
                HStack(spacing: VyronWorkspaceStyle.controlSpacing) {
                    addMenu
                    VyronProjectAccessMenu()
                    Spacer(minLength: 0)
                    VyronEffortControl()
                    voiceControls
                    if !showsLiveVoiceAction { VyronFollowUpActionsView(submit: submit) }
                }
            }
        }
        .padding(.horizontal, VyronWorkspaceStyle.composerPadding)
        .padding(.vertical, model.isChatWorkspace
            ? VyronWorkspaceStyle.chatComposerVerticalPadding : VyronWorkspaceStyle.composerPadding)
        .background(palette.raised, in: RoundedRectangle(
            cornerRadius: model.isChatWorkspace
                ? VyronWorkspaceStyle.chatComposerRadius : VyronWorkspaceStyle.composerRadius
        ))
    }

    private var composerInput: some View {
        VyronVoiceComposerInput(model: model, voice: model.voice, placeholder: placeholder, submit: submit)
    }

    private func submit() {
        if let sideID = model.submitComposer() {
            openWindow(id: VyronAppWindow.conversation, value: sideID)
        }
    }

    private var attachments: some View {
        let connectionName = model.modelSelection.activeConnectionName
        let imageHelp = model.screenshotAnalysisHint + "\n\n" + VyronScreenshotText.privacyHint(connectionName)
        let folderHelp = VyronFolderAttachmentText.privacyHint(connectionName)
        let pdfHelp = VyronFolderAttachmentText.pdfPrivacyHint(connectionName)
        let fileHelp = VyronFolderAttachmentText.filePrivacyHint(connectionName)
        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: VyronWorkspaceStyle.compactSpacing) {
                ForEach(model.composerAttachments.folderAttachmentDraft.folders) { folder in
                    VyronFolderAttachmentCard(folder: folder, privacyHint: folderHelp, remove: model.removeFolderAttachment)
                }
                ForEach(model.composerAttachments.applications) { application in
                    VyronApplicationAttachmentCard(attachment: application, remove: model.removeApplicationAttachment)
                }
                ForEach(model.composerAttachments.screenshotDraft.images) { image in
                    VyronScreenshotAttachmentCard(attachment: image, helpText: imageHelp, remove: model.removeScreenshot)
                }
                ForEach(model.composerAttachments.pdfs) { pdf in
                    let help = pdf.isTruncated ? pdfHelp + "\n" + VyronFolderAttachmentText.pdfLimited : pdfHelp
                    VyronPDFAttachmentCard(attachment: pdf.preview, helpText: help, remove: model.removePDFAttachment)
                }
                ForEach(model.composerAttachments.files) { file in
                    let help = file.isTruncated ? fileHelp + "\n" + VyronFolderAttachmentText.fileLimited : fileHelp
                    VyronFileAttachmentCard(info: file.info, helpText: help, remove: model.removeFileAttachment)
                }
            }
        }
    }

    private var voiceControls: some View {
        VyronVoiceControls(
            voice: model.voice,
            canStart: !isBusy && !model.isRunningScheduledTask && !model.isShuttingDown
                && !model.foregroundRun.isStoppingDevelopment && !model.composer.isEditingQueuedMessage,
            showsLiveConversation: showsLiveVoiceAction
        )
    }

    private var showsLiveVoiceAction: Bool {
        !isBusy && !model.composer.isEditingQueuedMessage
            && model.composer.trimmedDraft.isEmpty
            && !model.composerAttachments.hasDrafts && !model.composerAttachments.isImporting
            && model.isConversationModeCompatible(.chat)
    }

    private var addMenu: some View {
        Menu {
            Button(VyronFolderAttachmentText.fileChoose) { model.chooseFileAttachments() }
                .disabled(!model.canAttachFiles)
            Button(VyronFolderAttachmentText.chooseFolder) { model.chooseFolderAttachment() }
                .disabled(!model.canAttachFolders)
            Button(VyronScreenshotText.pickerTitle) { model.openScreenshotPicker() }
                .disabled(!model.canAttachScreenshots)
            Button(VyronScreenshotText.pasteImage) { model.pasteScreenshotImage() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .disabled(!model.canAttachScreenshots)
            Divider()
            Button(VyronWorkspaceText.newTask) { model.requestNewTask() }
            if !model.isChatWorkspace {
                Button(VyronWorkspaceText.openProject) { model.chooseWorkspace() }
            }
            Divider()
            Button(VyronWorkspaceText.manageModels) { model.appNavigation.showSetup = true }
            Button(VyronWorkspaceText.advancedTools) { model.appNavigation.showAutomation = true }
        } label: {
            Image(systemName: VyronSymbols.plus)
                .font(VyronWorkspaceStyle.inputFont)
                .foregroundStyle(palette.text)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .tint(palette.text)
        .help(VyronWorkspaceText.addActions)
        .accessibilityLabel(VyronWorkspaceText.addActions)
    }

    private var contextStrip: some View {
        HStack(spacing: VyronWorkspaceStyle.controlSpacing) {
            VyronComposerProjectMenu()
            Button {
                if model.appNavigation.showWorkspace && model.inspector.inspectorTab == .files {
                    model.appNavigation.showWorkspace = false
                } else {
                    model.inspector.inspectorTab = .files
                    model.appNavigation.showWorkspace = true
                }
            } label: {
                Label(VyronWorkspaceText.files, systemImage: VyronSymbols.files)
            }
            .foregroundStyle(model.appNavigation.showWorkspace ? palette.text : palette.muted)
            Button {
                model.openPlugins()
            } label: {
                Label(VyronWorkspaceText.plugins, systemImage: VyronSymbols.plugins)
            }
            Spacer(minLength: 0)
            Button {
                model.inspector.showTerminal.toggle()
            } label: {
                Image(systemName: VyronSymbols.terminal)
                    .foregroundStyle(model.inspector.showTerminal ? palette.text : palette.muted)
            }
            .help(VyronWorkspaceText.toggleTerminal)
            .accessibilityLabel(VyronWorkspaceText.toggleTerminal)
        }
        .font(VyronWorkspaceStyle.controlFont)
        .foregroundStyle(palette.text)
        .buttonStyle(.plain)
        .padding(.horizontal, VyronWorkspaceStyle.composerPadding)
        .frame(height: VyronWorkspaceStyle.contextHeight)
        .background(palette.surface, in: UnevenRoundedRectangle(
            bottomLeadingRadius: VyronWorkspaceStyle.contextRadius,
            bottomTrailingRadius: VyronWorkspaceStyle.contextRadius
        ))
        .padding(.horizontal, VyronWorkspaceStyle.contextInset)
    }

    private func errorNotice(_ error: VyronWorkspaceError) -> some View {
        HStack(alignment: .top, spacing: VyronWorkspaceStyle.compactSpacing) {
            Image(systemName: VyronSymbols.warning).foregroundStyle(palette.danger)
            VStack(alignment: .leading, spacing: VyronWorkspaceStyle.compactSpacing) {
                Text(verbatim: error.message)
                    .foregroundStyle(palette.danger)
                    .textSelection(.enabled)
                if error.showsLocalContextBudgetHelp, model.modelSelection.isBuiltinConnection {
                    Text(VyronWorkspaceText.localContextBudgetHint(
                        VyronAppText.settingsContextBudget,
                        VyronAppText.settingsLocalModelSettings
                    ))
                    .foregroundStyle(palette.muted)
                    Button(VyronWorkspaceText.manageModels) {
                        model.appNavigation.showSetup = true
                    }
                    .buttonStyle(QuietButtonStyle(foreground: palette.controlAccent))
                }
            }
            Spacer(minLength: 0)
            Button {
                model.errorMessage = nil
            } label: {
                Image(systemName: VyronSymbols.close)
            }
            .buttonStyle(.plain)
            .help(VyronWorkspaceText.dismissError)
            .accessibilityLabel(VyronWorkspaceText.dismissError)
        }
        .font(VyronWorkspaceStyle.captionFont)
        .padding(VyronWorkspaceStyle.composerPadding)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: VyronWorkspaceStyle.errorRadius))
    }

    private var placeholder: String {
        switch model.composer.mode {
        case .agent:
            model.workspaceState.workspaceURL == nil
                ? VyronWorkspaceText.placeholderNoProject : VyronWorkspaceText.placeholderWork
        case .plan: VyronWorkspaceText.placeholderPlan
        case .chat: VyronWorkspaceText.placeholderChat
        }
    }
}
