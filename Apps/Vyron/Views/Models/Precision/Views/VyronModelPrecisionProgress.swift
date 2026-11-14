import SwiftUI

struct VyronModelPrecisionProgress: View {
    @Environment(\.vyronPalette) private var palette
    @EnvironmentObject private var model: AppModel
    @ObservedObject var downloads: VyronModelDownloads
    let transfer: VyronModelTransfer
    let change: VyronModelPrecisionChange

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(downloads.isRemovingPreviousVariant
                    ? VyronAppText.settingsRemovingPreviousVariant(change.original.name)
                    : VyronAppText.settingsChangingPrecision(transfer.tag))
                    .font(VyronWorkspaceStyle.captionFont)
                Spacer()
                if !downloads.isRemovingPreviousVariant {
                    Button(VyronAppText.settingsCancel) { model.cancelDownload() }
                        .font(VyronWorkspaceStyle.captionFont)
                        .buttonStyle(QuietButtonStyle())
                }
            }
            if !downloads.isRemovingPreviousVariant,
                let progress = downloads.progressByTag[transfer.tag], progress.phase != .modelFilesReady,
                let fraction = progress.fraction {
                ProgressView(value: fraction).tint(palette.accent)
            } else {
                ProgressView().progressViewStyle(.linear).tint(palette.accent)
            }
        }
        .padding(VyronSettingsStyle.modelManagerInset)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}
