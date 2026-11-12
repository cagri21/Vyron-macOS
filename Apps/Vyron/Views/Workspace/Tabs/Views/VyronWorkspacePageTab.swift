import SwiftUI

struct VyronWorkspacePageTab: View {
    @EnvironmentObject private var presentation: VyronWorkspaceTabsPresentation
    @ObservedObject var session: VyronWorkspacePageSession
    @State private var saveError: String?
    @FocusState private var focusesTitle: Bool
    let tabID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: VyronWorkspaceToolsStyle.padding) {
            HStack {
                Text(session.hasChanges || !session.isSaved ? VyronBrowserText.unsavedPage : VyronToolsText.localPageHint)
                    .font(VyronWorkspaceToolsStyle.captionFont).foregroundStyle(Palette.muted)
                Spacer()
                Button(VyronBrowserText.savePage) {
                    saveError = presentation.savePage(in: tabID) ? nil : presentation.library.errorMessage
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
            TextField(VyronToolsText.pageTitle, text: $session.draft.title)
                .focused($focusesTitle)
                .textFieldStyle(.plain).font(VyronWorkspaceTabsStyle.pageTitleFont)
                .accessibilityLabel(VyronToolsText.pageTitle)
            Divider()
            ZStack(alignment: .topLeading) {
                if session.draft.body.isEmpty {
                    Text(VyronToolsText.pageBody)
                        .foregroundStyle(Palette.muted).padding(.top, VyronWorkspaceToolsStyle.gridSpacing)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $session.draft.body)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel(VyronToolsText.pageBody)
            }
            .font(VyronWorkspaceTabsStyle.pageBodyFont)
            if let saveError {
                Text(saveError).font(VyronWorkspaceToolsStyle.captionFont)
                    .foregroundStyle(Palette.muted).textSelection(.enabled)
            }
        }
        .padding(VyronWorkspaceToolsStyle.sectionSpacing)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas).foregroundStyle(Palette.text)
        .onChange(of: session.draft.title) { _, _ in presentation.tabs.updatePageTitle(session.draft) }
        .onAppear { focusesTitle = true }
    }
}
