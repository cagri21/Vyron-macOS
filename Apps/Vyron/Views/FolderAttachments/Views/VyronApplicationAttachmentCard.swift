import AppKit
import SwiftUI
import VyronModelDomain

struct VyronApplicationAttachmentCard: View {
    let attachment: VyronApplicationAttachment
    let remove: ((UUID) -> Void)?

    @State private var isOpening = false
    @State private var showsOpenError = false

    var body: some View {
        HStack(spacing: VyronWorkspaceStyle.compactSpacing) {
            Button(action: open) {
                HStack(spacing: VyronWorkspaceStyle.compactSpacing) {
                    Image(systemName: VyronSymbols.computerPreview)
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                    Text(verbatim: attachment.name)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: VyronSymbols.externalOpen)
                        .foregroundStyle(Palette.muted)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isOpening)
            .help(VyronFolderAttachmentText.applicationOpen(attachment.name))
            .accessibilityLabel(VyronFolderAttachmentText.applicationOpen(attachment.name))

            if let remove {
                Button { remove(attachment.id) } label: {
                    Image(systemName: VyronSymbols.close)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.muted)
                .help(VyronFolderAttachmentText.remove(attachment.name))
                .accessibilityLabel(VyronFolderAttachmentText.remove(attachment.name))
            }
        }
        .font(VyronWorkspaceStyle.controlFont)
        .padding(VyronWorkspaceStyle.compactSpacing)
        .frame(maxWidth: VyronFileAttachmentStyle.maximumCardWidth, alignment: .leading)
        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: VyronWorkspaceStyle.errorRadius))
        .alert(VyronToolsText.openFailed, isPresented: $showsOpenError) {}
    }

    private func open() {
        guard !isOpening else { return }
        let url = attachment.url
        guard attachment.path.hasPrefix("/"), url.pathExtension.lowercased() == "app" else {
            showsOpenError = true
            return
        }
        isOpening = true
        Task { @MainActor in
            defer { isOpening = false }
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    showsOpenError = true
                    return
                }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                configuration.allowsRunningApplicationSubstitution = false
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            } catch {
                showsOpenError = true
            }
        }
    }
}
