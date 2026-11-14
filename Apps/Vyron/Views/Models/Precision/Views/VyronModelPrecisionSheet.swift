import SwiftUI
import VyronModelData
import VyronModelDomain

struct VyronModelPrecisionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @State private var options: VyronModelPrecisionOptions?
    @State private var selectedVariantID = ""
    @State private var failure: String?
    @State private var reload = 0

    let installed: LocalModel

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronSettingsStyle.modelManagerInset) {
            Text(VyronAppText.settingsChangePrecisionTitle(installed.name))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let options, !options.variants.isEmpty {
                variantPicker(options)
            } else if let failure {
                failureNotice(failure)
                Button(VyronAppText.settingsRefresh) { reload += 1 }
            } else if options != nil {
                Text(VyronAppText.settingsNoReplacementVariants).foregroundStyle(Palette.muted)
            } else {
                ProgressView(VyronAppText.settingsFindingVariants)
            }
            HStack {
                Spacer()
                Button(VyronAppText.settingsCancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if let options, let selectedVariant {
                    let isInstalled = options.installedVariantIDs.contains(selectedVariant.id)
                    let actionTitle = isInstalled
                        ? VyronAppText.settingsSwitchVariant : VyronAppText.settingsDownloadAndSwitchVariant
                    Button(actionTitle) {
                        let change = VyronModelPrecisionChange(
                            original: options.original, replacement: selectedVariant,
                            connectionRevision: options.connectionRevision, mayDownloadReplacement: !isInstalled
                        )
                        if model.changeModelPrecision(change) { dismiss() }
                        else { failure = VyronAppText.settingsPrecisionReplacementUnavailable }
                    }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(!model.canChangeLocalModelPrecision)
                }
            }
        }
        .padding(VyronSettingsStyle.modelManagerInset)
        .frame(width: 480)
        .task(id: reload) { await load() }
    }

    private var selectedVariant: ModelSourceVariant? {
        options?.variants.first { $0.id == selectedVariantID }
    }

    private func variantPicker(_ options: VyronModelPrecisionOptions) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Picker(VyronAppText.settingsVariant, selection: $selectedVariantID) {
                ForEach(options.variants) { variant in
                    let precision = variant.quantization.map(VyronModelPrecisionLabel.text)
                    Text([precision, variant.name].compactMap { $0 }.joined(separator: " · ")).tag(variant.id)
                }
            }
            .onChange(of: selectedVariantID) { _, _ in failure = nil }
            if let size = selectedVariant?.sizeBytes {
                Text(VyronAppText.settingsWeightSize(size.fileSizeLabel))
                    .font(VyronWorkspaceStyle.captionFont).foregroundStyle(Palette.muted)
            }
            if let tag = selectedVariant?.ollamaTag {
                Label(
                    VyronAppText.settingsPrecisionReplacementWarning(options.original.name, tag),
                    systemImage: VyronSymbols.warning
                )
                .foregroundStyle(Palette.warning)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let failure { failureNotice(failure) }
        }
    }

    private func failureNotice(_ message: String) -> some View {
        Label(message, systemImage: VyronSymbols.warning)
            .foregroundStyle(Palette.warning)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func load() async {
        failure = nil
        do {
            let loaded = try await model.precisionOptions(for: installed)
            try Task.checkCancellation()
            selectedVariantID = loaded.variants.first?.id ?? ""
            options = loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            failure = error.localizedDescription
        }
    }
}
