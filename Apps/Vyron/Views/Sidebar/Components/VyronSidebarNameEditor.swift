import SwiftUI

struct VyronSidebarNameEditor: View {
    @Environment(\.locale) private var localizationLocale
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var error: String?
    @State private var isSaving = false
    @FocusState private var nameFocused: Bool
    let title: String
    let onSave: (String) -> String?

    init(title: String, initialValue: String, onSave: @escaping (String) -> String?) {
        self.title = title
        _name = State(initialValue: initialValue)
        self.onSave = onSave
    }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronSidebarStyle.headerInset) {
            Text(title).font(VyronSidebarStyle.editorTitleFont)
            TextField(VyronSidebarText.name, text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(save)
            Text(VyronSidebarText.savedNote)
                .font(VyronSidebarStyle.captionFont)
                .foregroundStyle(Palette.muted)
            if let error {
                Text(error).font(VyronSidebarStyle.detailFont).foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(VyronSidebarText.cancel, role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(VyronSidebarText.save, action: save).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
        .padding(VyronSidebarStyle.editorPadding)
        .frame(width: VyronSidebarStyle.editorWidth)
        .background(Palette.canvas)
        .foregroundStyle(Palette.text)
        .tint(Palette.controlAccent)
        .onAppear { nameFocused = true }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        if let failure = onSave(name) {
            error = failure
            isSaving = false
        } else {
            dismiss()
        }
    }
}
