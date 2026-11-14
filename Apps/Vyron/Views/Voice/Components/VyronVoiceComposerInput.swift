import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VyronVoiceComposerInput: View {
    @Environment(\.locale) private var localizationLocale
    @ObservedObject var model: AppModel
    @ObservedObject var voice: VyronVoiceModel
    let placeholder: String
    let submit: () -> Void
    @FocusState private var inputFocused: Bool

    private var isInputDisabled: Bool {
        model.computerWork.isComputerWorkActive || model.isRunningScheduledTask || model.isShuttingDown || voice.isActive
    }

    var body: some View {
        let _ = localizationLocale
        let suggestion = model.composerSuggestion
        HStack(alignment: .top, spacing: VyronWorkspaceStyle.compactSpacing) {
            TextField(
                "",
                text: Binding(get: { model.composer.draft }, set: { model.composer.draft = $0 }),
                axis: .vertical
            )
                .textFieldStyle(.plain)
                .font(VyronWorkspaceStyle.inputFont)
                .lineLimit(model.isChatWorkspace ? 1...6 : 2...6)
                .disabled(isInputDisabled)
                .overlay(alignment: .topLeading) {
                    if model.composer.draft.isEmpty {
                        Text(verbatim: suggestion?.text ?? placeholder)
                            .font(VyronWorkspaceStyle.inputFont)
                            .foregroundStyle(Palette.muted)
                            .lineLimit(VyronWorkspaceStyle.composerHintLineLimit)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel(VyronWorkspaceText.taskInput)
                .accessibilityHint(
                    (suggestion.map { $0.text + "\n" + VyronGeneralText.suggestedQuestionTabHint } ?? placeholder)
                        + "\n" + VyronWorkspaceText.composerKeyboardHint
                        + "\n" + VyronSkillText.composerHint
                )
                .focused($inputFocused)
                .onPasteCommand(of: [.fileURL]) { providers in
                    guard inputFocused, !isInputDisabled else { return }
                    _ = model.acceptComposerDrop(providers)
                }
                .background {
                    VyronComposerPasteShortcut(isEnabled: inputFocused && !isInputDisabled) {
                        model.pasteComposerAttachments()
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .onKeyPress(.return, phases: .down) { keyPress in
                    guard inputFocused, !isInputDisabled else { return .ignored }
                    return VyronComposerReturnKey.handle(
                        modifiers: keyPress.modifiers,
                        editor: NSApp.keyWindow?.firstResponder as? NSTextInputClient
                    ) {
                        if model.sideChatCommand != nil || !acceptSkillSelection(runsSideChat: true) { submit() }
                    }
                }
                .onKeyPress(.tab, phases: .down) { keyPress in
                    guard inputFocused, !isInputDisabled, keyPress.modifiers.isEmpty else { return .ignored }
                    if let editor = NSApp.keyWindow?.firstResponder as? NSTextInputClient, editor.hasMarkedText() {
                        return .ignored
                    }
                    if acceptSkillSelection() { return .handled }
                    guard let suggestion = model.composerSuggestion else { return .ignored }
                    model.acceptComposerSuggestion(suggestion)
                    return .handled
                }
                .onKeyPress(.upArrow, phases: .down) { keyPress in
                    moveSkillSelection(by: -1, keyPress: keyPress)
                }
                .onKeyPress(.downArrow, phases: .down) { keyPress in
                    moveSkillSelection(by: 1, keyPress: keyPress)
                }
                .onKeyPress(.escape, phases: .down) { keyPress in
                    guard inputFocused, !isInputDisabled, keyPress.modifiers.isEmpty,
                        model.composerSkills.isPresented
                    else { return .ignored }
                    if let editor = NSApp.keyWindow?.firstResponder as? NSTextInputClient, editor.hasMarkedText() {
                        return .ignored
                    }
                    model.composerSkills.dismiss()
                    return .handled
                }
                .onChange(of: model.composer.isEditingQueuedMessage) { _, editing in
                    if editing { inputFocused = true }
                }
            if let suggestion {
                Button {
                    model.acceptComposerSuggestion(suggestion)
                    inputFocused = true
                } label: {
                    Image(systemName: VyronSymbols.acceptSuggestion)
                        .font(VyronWorkspaceStyle.composerHintKeyFont)
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, VyronWorkspaceStyle.composerHintKeyHorizontalPadding)
                        .padding(.vertical, VyronWorkspaceStyle.composerHintKeyVerticalPadding)
                        .background(
                            Palette.surface,
                            in: RoundedRectangle(cornerRadius: VyronWorkspaceStyle.composerHintKeyRadius)
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)
                .padding(.top, VyronWorkspaceStyle.composerHintKeyTopPadding)
                .accessibilityLabel(VyronGeneralText.acceptSuggestedQuestion)
                .help(VyronGeneralText.suggestedQuestionTabHint)
            }
        }
    }

    private func acceptSkillSelection(runsSideChat: Bool = false) -> Bool {
        let skills = model.composerSkills
        skills.updateDraft(model.composer.draft)
        guard skills.isPresented else { return false }
        if let command = skills.selectedCommand,
            let replacement = skills.replacement(for: command, in: model.composer.draft) {
            model.composer.draft = replacement
            if runsSideChat, case .side = command, model.sideChatCommand != nil { submit() }
        }
        return true
    }

    private func moveSkillSelection(by offset: Int, keyPress: KeyPress) -> KeyPress.Result {
        guard inputFocused, !isInputDisabled, keyPress.modifiers.isEmpty else { return .ignored }
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextInputClient, editor.hasMarkedText() {
            return .ignored
        }
        let skills = model.composerSkills
        skills.updateDraft(model.composer.draft)
        guard skills.isPresented else { return .ignored }
        skills.moveSelection(by: offset)
        return .handled
    }
}
