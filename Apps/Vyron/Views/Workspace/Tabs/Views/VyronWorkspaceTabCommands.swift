import SwiftUI

struct VyronWorkspaceTabCommands: Commands {
    @FocusedObject private var presentation: VyronWorkspaceTabsPresentation?

    var body: some Commands {
        CommandMenu(VyronBrowserText.tabs) {
            Button(VyronBrowserText.newTab) { presentation?.newTab() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(presentation == nil)
            if let presentation {
                Divider()
                ForEach(presentation.tabs.tabs) { tab in
                    Button(tab.title) { presentation.tabs.select(tab.id) }
                }
            }
        }
    }
}
