import SwiftUI
import VyronCore

struct VyronModelFeatureNotice: View {
    @Environment(\.vyronPalette) private var palette
    let report: VyronModelFeatureReport
    @Environment(\.locale) private var locale
    @State private var isExpanded = false

    var body: some View {
        let _ = locale
        DisclosureGroup(isExpanded: $isExpanded) {
            details
                .padding(.top, VyronWorkspaceStyle.compactSpacing)
                .textSelection(.enabled)
        } label: {
            Label(VyronAppText.modelFeaturesTitle, systemImage: VyronSymbols.model)
                .font(VyronWorkspaceStyle.captionFont)
                .foregroundStyle(palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
        }
        .font(VyronWorkspaceStyle.captionFont)
        .tint(palette.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, VyronWorkspaceStyle.composerPadding)
        .padding(.vertical, isExpanded ? VyronWorkspaceStyle.composerPadding : VyronWorkspaceStyle.compactSpacing)
        .background {
            if isExpanded {
                RoundedRectangle(cornerRadius: VyronSettingsStyle.rowRadius)
                    .fill(palette.surface)
            }
        }
        .help(VyronAppText.modelFeaturesDetails)
        .accessibilityElement(children: .contain)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: VyronWorkspaceStyle.compactSpacing) {
            if !report.unavailableFeatures.isEmpty {
                Text(VyronAppText.modelFeaturesUnavailableList(names(report.unavailableFeatures)))
                    .foregroundStyle(palette.warning)
            }
            let unverified = report.features.filter { $0.status == .unverified }
            if !unverified.isEmpty {
                Text(VyronAppText.modelFeaturesUnverifiedList(names(unverified)))
                    .foregroundStyle(palette.muted)
            }
            let available = report.features.filter { $0.status == .available }
            if !available.isEmpty {
                Text(VyronAppText.modelFeaturesAvailableList(names(available)))
                    .foregroundStyle(palette.muted)
            }
            ForEach(report.features, id: \.feature) { availability in
                VStack(alignment: .leading, spacing: VyronSettingsStyle.textSpacing) {
                    HStack {
                        Text(VyronModelFeaturePresentation.title(availability.feature))
                        Spacer(minLength: VyronWorkspaceStyle.compactSpacing)
                        Text(VyronModelFeaturePresentation.status(availability.status))
                            .foregroundStyle(availability.status == .unavailable ? palette.warning : palette.muted)
                    }
                    if let reason = VyronModelFeaturePresentation.reason(availability.reason) {
                        Text(verbatim: reason).foregroundStyle(palette.muted)
                    }
                }
            }
            Text(VyronAppText.modelFeaturesBudgetHint).foregroundStyle(palette.muted)
        }
    }

    private func names(_ features: [VyronModelFeatureAvailability]) -> String {
        features.map { VyronModelFeaturePresentation.title($0.feature) }.joined(separator: ", ")
    }
}
