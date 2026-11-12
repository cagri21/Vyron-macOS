import SwiftUI

struct VyronChatWelcomeActions: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: 0) {
            action(VyronScreenshotText.pickerTitle, symbol: VyronSymbols.screenshot) {
                model.openScreenshotPicker()
            }
            .disabled(!model.canAttachScreenshots)
            action(VyronWorkspaceText.writeOrEdit, symbol: VyronSymbols.pencil) {
                model.usePrompt(VyronWorkspaceText.writePrompt)
            }
            action(VyronWorkspaceText.searchWeb, symbol: VyronSymbols.web) {
                model.usePrompt(VyronWorkspaceText.searchPrompt)
            }
        }
        .font(VyronWorkspaceStyle.inputFont)
        .foregroundStyle(Palette.muted)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, VyronWorkspaceStyle.composerPadding)
    }

    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, minHeight: VyronWorkspaceStyle.welcomeActionHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
    }
}
