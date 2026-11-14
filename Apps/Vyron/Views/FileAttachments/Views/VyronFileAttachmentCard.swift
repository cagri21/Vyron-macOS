import SwiftUI
import VyronModelDomain

struct VyronFileAttachmentCard: View {
    let info: VyronFileAttachmentInfo
    var helpText: String?
    var remove: ((UUID) -> Void)?

    var body: some View {
        HStack(spacing: VyronWorkspaceStyle.compactSpacing) {
            Label {
                Text(verbatim: fileType)
                    .fontWeight(.semibold)
            } icon: {
                Image(systemName: info.kind == .audio ? VyronSymbols.liveVoice : VyronSymbols.attachmentDocument)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(info.kind == .audio ? Palette.effortAccent : Palette.diffAdded)
            .accessibilityHidden(true)
            Text(verbatim: info.name)
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
                .accessibilityLabel(Text(verbatim: info.name + ", " + fileType))
            if let remove {
                Button { remove(info.id) } label: {
                    Image(systemName: VyronSymbols.close)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.muted)
                .help(VyronFolderAttachmentText.remove(info.name))
                .accessibilityLabel(VyronFolderAttachmentText.remove(info.name))
            }
        }
        .font(VyronWorkspaceStyle.controlFont)
        .padding(VyronWorkspaceStyle.compactSpacing)
        .frame(maxWidth: VyronFileAttachmentStyle.maximumCardWidth, alignment: .leading)
        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: VyronWorkspaceStyle.errorRadius))
        .help(details)
    }

    private var fileType: String {
        let extensionName = (info.name as NSString).pathExtension.uppercased()
        guard !extensionName.isEmpty else {
            return info.kind == .audio
                ? VyronFolderAttachmentText.fileAudioType : VyronFolderAttachmentText.fileDocumentType
        }
        return String(extensionName.prefix(12))
    }

    private var details: String {
        var lines = [info.name]
        if let helpText { lines.append(helpText) }
        if info.kind == .audio, info.hasTranscript == false {
            lines.append(VyronFolderAttachmentText.fileAudioNoTranscript)
        }
        return lines.joined(separator: "\n")
    }
}
