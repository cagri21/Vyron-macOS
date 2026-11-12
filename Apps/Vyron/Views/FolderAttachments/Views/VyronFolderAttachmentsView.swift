import SwiftUI

struct VyronFolderAttachmentsView: View {
    let folders: [VyronFolderAttachment]
    let remove: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VyronWorkspaceStyle.compactSpacing) {
            ForEach(folders) { folder in
                HStack(spacing: VyronWorkspaceStyle.controlSpacing) {
                    Image(systemName: VyronSymbols.folder)
                        .foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: VyronWorkspaceStyle.compactSpacing) {
                        Text(verbatim: folder.name).lineLimit(1)
                        Text(VyronFolderAttachmentText.summary(
                            folder.summary.includedFileCount, folder.summary.skippedFileCount
                        ))
                        .foregroundStyle(Palette.muted)
                        if folder.summary.isLimited {
                            Text(VyronFolderAttachmentText.limited).foregroundStyle(Palette.muted)
                        }
                    }
                    Spacer(minLength: 0)
                    Button { remove(folder.id) } label: {
                        Image(systemName: VyronSymbols.close)
                    }
                    .buttonStyle(.plain)
                    .help(VyronFolderAttachmentText.remove(folder.name))
                    .accessibilityLabel(VyronFolderAttachmentText.remove(folder.name))
                }
                .padding(VyronWorkspaceStyle.composerPadding)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: VyronWorkspaceStyle.errorRadius))
            }
        }
        .font(VyronWorkspaceStyle.captionFont)
    }
}
