import SwiftUI

struct VyronWorkspaceLinkEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: VyronWorkspaceLibraryModel
    @State private var title = ""
    @State private var address = ""

    var body: some View {
        VStack(alignment: .leading, spacing: VyronWorkspaceToolsStyle.padding) {
            Text(VyronToolsText.addLink).font(VyronWorkspaceToolsStyle.titleFont)
            TextField(VyronToolsText.linkTitle, text: $title)
            TextField(VyronToolsText.linkAddress, text: $address)
                .onSubmit(save)
            if let error = library.errorMessage {
                Text(error).font(VyronWorkspaceToolsStyle.captionFont).foregroundStyle(Palette.muted)
                    .textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button(VyronToolsText.cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(VyronToolsText.save, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(VyronWorkspaceToolsStyle.sectionSpacing)
        .frame(width: VyronWorkspaceToolsStyle.linkEditorWidth)
        .background(Palette.canvas).foregroundStyle(Palette.text)
    }

    private func save() {
        if library.addLink(title: title, address: address) { dismiss() }
    }
}
