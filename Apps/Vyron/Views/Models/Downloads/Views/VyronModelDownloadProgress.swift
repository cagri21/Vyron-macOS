import SwiftUI
import VyronModelDomain

struct VyronModelDownloadProgress: View {
    @Environment(\.locale) private var localizationLocale
    let progress: ModelPullProgress?
    let isImport: Bool
    let cancel: () -> Void

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(status).font(.system(size: 10)).lineLimit(1)
                Spacer()
                if let fraction = progress?.fraction {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.accent)
                }
                Button(isImport ? VyronAppText.settingsCancelImport : VyronAppText.settingsPause, action: cancel)
                    .font(.system(size: 10, weight: .medium)).buttonStyle(.plain).foregroundStyle(Palette.muted)
            }
            if let fraction = progress?.fraction {
                ProgressView(value: fraction).tint(Palette.accent)
            } else {
                ProgressView().progressViewStyle(.linear).tint(Palette.accent)
            }
            if let complete = progress?.completed, let total = progress?.total {
                Text(VyronAppText.settingsDownloadProgress(complete.fileSizeLabel, total.fileSizeLabel))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
            }
        }
    }

    private var status: String {
        guard let progress else { return VyronAppText.settingsPreparingDownload }
        switch progress.phase {
        case .findingModelFiles: return VyronAppText.settingsFindingModelFiles
        case .downloadingModelFiles: return VyronAppText.settingsDownloadingModelFiles
        case .checkingFiles, .verifyingGGUF: return VyronAppText.settingsCheckingFiles
        case .modelFilesReady: return VyronAppText.settingsModelFilesReady
        case .finishingSetup, .downloadingGGUF, .importingModelWeights, nil:
            return VyronAppText.settingsFinishingSetup
        }
    }
}
