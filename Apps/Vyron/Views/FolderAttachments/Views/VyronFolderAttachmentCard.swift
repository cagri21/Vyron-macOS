import SwiftUI

struct VyronFolderAttachmentCard: View {
    @Environment(\.vyronPalette) private var palette
    let folder: VyronFolderAttachment
    let privacyHint: String
    let remove: (UUID) -> Void

    var body: some View {
        HStack(spacing: VyronWorkspaceStyle.compactSpacing) {
            Image(systemName: VyronSymbols.folder)
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text(verbatim: folder.name)
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: VyronWorkspaceStyle.projectLabelWidth, alignment: .leading)
                .help(details)
            Button { remove(folder.id) } label: {
                Image(systemName: VyronSymbols.close)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.muted)
            .help(VyronFolderAttachmentText.remove(folder.name))
            .accessibilityLabel(VyronFolderAttachmentText.remove(folder.name))
        }
        .font(VyronWorkspaceStyle.controlFont)
        .padding(VyronWorkspaceStyle.compactSpacing)
        .background(palette.canvas, in: RoundedRectangle(cornerRadius: VyronWorkspaceStyle.errorRadius))
    }

    private var details: String {
        let summary = VyronFolderAttachmentText.summary(folder.summary.includedFileCount, folder.summary.skippedFileCount)
        var lines = [folder.name, summary]
        if folder.summary.isLimited { lines.append(VyronFolderAttachmentText.limited) }
        lines.append(privacyHint)
        return lines.joined(separator: "\n")
    }
}
