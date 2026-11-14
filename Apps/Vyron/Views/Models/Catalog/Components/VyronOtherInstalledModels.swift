import SwiftUI
import VyronModelDomain

struct VyronOtherInstalledModels: View {
    @EnvironmentObject private var model: AppModel
    let onChangePrecision: (LocalModel) -> Void

    var body: some View {
        let ranking = model.modelRanking
        let uncatalogued = ranking.allModels.filter { ModelCatalog.descriptor(for: $0.name) == nil }
        if !uncatalogued.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: VyronAppText.settingsOtherModels)
                ForEach(uncatalogued) { local in
                    modelRow(local, score: ranking.score(for: local.name))
                }
            }
        }
    }

    private func modelRow(_ local: LocalModel, score: Double?) -> some View {
        let precision = local.quantization.map(VyronModelPrecisionLabel.text)
        return HStack(spacing: 9) {
            Image(systemName: VyronSymbols.modelSource).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(local.name).font(.system(size: 11, weight: .medium, design: .monospaced))
                Text([local.size.fileSizeLabel, local.parameterSize, precision].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 9)).foregroundStyle(Palette.muted)
                VyronModelScoreLabel(score: score)
            }
            Spacer()
            VyronChangeModelPrecisionButton(installed: local, onOpen: onChangePrecision)
            if model.modelSelection.isSelectedModel(local.name) {
                Text(VyronAppText.settingsSelected).font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 7).padding(.vertical, 5)
                    .background(Palette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
            } else {
                Button(VyronAppText.settingsUseModel) { model.useLocalModel(local.name) }
                    .font(.system(size: 11, weight: .medium)).buttonStyle(.plain).foregroundStyle(Palette.accent)
                    .disabled(!model.canManageModelSelection)
            }
        }
        .padding(.vertical, 4)
    }
}
