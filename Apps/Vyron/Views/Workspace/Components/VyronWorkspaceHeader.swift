import SwiftUI

struct VyronWorkspaceHeader: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let _ = localizationLocale
        HStack(spacing: 0) {
            modeButton(VyronWorkspaceText.chat, mode: .chat)
            modeButton(VyronWorkspaceText.work, mode: .agent)
        }
        .padding(VyronWorkspaceStyle.modeInset)
        .background(Palette.surface, in: Capsule())
        .frame(maxWidth: .infinity)
        .frame(height: VyronWorkspaceHeaderStyle.height)
    }

    private func modeButton(_ title: String, mode: ComposerMode) -> some View {
        let selected = mode == .chat ? model.composer.mode == .chat : model.composer.mode != .chat
        return Button {
            if !selected { model.selectComposerMode(mode) }
        } label: {
            Text(title)
                .font(VyronWorkspaceStyle.modeFont)
                .foregroundStyle(selected ? Palette.text : Palette.muted)
                .frame(width: VyronWorkspaceStyle.modeWidth, height: VyronWorkspaceStyle.modeHeight)
                .background(selected ? Palette.field : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(selected ? Palette.border : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!model.canSelectComposerMode(mode))
        .help(model.composerModeAvailabilityDescription(mode) ?? title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

}
