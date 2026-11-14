import SwiftUI
import VyronCore

struct VyronComposerModelMenu: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    var isCompact = false

    var body: some View {
        let _ = localizationLocale
        Menu {
            modelChoices.disabled(!model.canManageModelSelection || model.modelDownloads.isActive)
            Divider()
            connectionChoices.disabled(!model.canManageModelSelection || model.modelDownloads.isActive)
            Divider()
            if !model.isChatWorkspace {
                Toggle(VyronWorkspaceText.plan, isOn: Binding(
                    get: { model.composer.mode == .plan },
                    set: { enabled in model.selectComposerMode(enabled ? .plan : .agent) }
                ))
                .disabled(!model.canSelectComposerMode(model.composer.mode == .plan ? .agent : .plan))
                .help(VyronWorkspaceText.planAccessDescription)
            }
            Divider()
            featureDetails
            Divider()
            Button(VyronWorkspaceText.manageModels) { model.appNavigation.showSetup = true }
                .disabled(!model.canManageModelSelection || model.modelDownloads.isActive)
        } label: {
            HStack(spacing: isCompact ? VyronWorkspaceStyle.modelSubtitleSpacing : VyronWorkspaceStyle.compactSpacing) {
                if !isCompact && !model.isChatWorkspace { Image(systemName: VyronSymbols.model) }
                Text(verbatim: selectionLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(VyronWorkspaceStyle.controlFont)
            .foregroundStyle(isCompact ? palette.muted : palette.text)
            .frame(maxWidth: VyronWorkspaceStyle.modelLabelWidth)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .font(VyronWorkspaceStyle.controlFont)
        .controlSize(isCompact ? .small : .regular)
        .tint(isCompact || model.isChatWorkspace ? palette.muted : palette.text)
        .fixedSize(horizontal: false, vertical: true)
        .disabled(!model.canManageModelSelection || model.modelDownloads.isActive)
        .help(VyronWorkspaceText.modelSelection)
        .accessibilityLabel(VyronWorkspaceText.modelSelection)
    }

    private var selectionLabel: String {
        VyronInferenceSelectionPresentation.modelName(
            model.modelSelection.selectedModel, automatic: model.modelSelection.automaticModelSelection
        )
    }

    private var featureDetails: some View {
        Menu(VyronAppText.modelFeaturesTitle) {
            ForEach(model.modelFeatureReport.features, id: \.feature) { availability in
                Section(VyronModelFeaturePresentation.title(availability.feature)) {
                    Text(VyronModelFeaturePresentation.status(availability.status))
                    if let reason = VyronModelFeaturePresentation.reason(availability.reason) {
                        Text(verbatim: reason)
                    }
                }
            }
            Text(VyronAppText.modelFeaturesBudgetHint)
            if model.modelFeatures.isVerifying {
                Text(VyronAppText.modelFeaturesChecking)
            } else if model.modelFeatureReport.features.contains(where: { $0.status == .unverified }) {
                Button(VyronAppText.modelFeaturesRetry) { model.retryModelFeatureVerification() }
                    .disabled(!model.canManageModelSelection || !model.modelSelection.isConnected)
            }
        }
    }

    @ViewBuilder
    private var modelChoices: some View {
        let ranking = model.modelRanking
        if model.modelSelection.isBuiltinConnection {
            Button {
                model.useAutomaticModels()
            } label: {
                if model.modelSelection.automaticModelSelection {
                    Label(VyronWorkspaceText.chooseAutomaticModel, systemImage: VyronSymbols.checkmark)
                } else {
                    Text(VyronWorkspaceText.chooseAutomaticModel)
                }
            }
            Divider()
        }
        if !ranking.scoredModels.isEmpty {
            Section(VyronModelRankingText.title) {
                ForEach(ranking.scoredModels) { ranked in
                    modelChoice(
                        ranked.model,
                        title: VyronModelScorePresentation.choice(ranked, locale: localizationLocale)
                    )
                }
            }
        }
        if !ranking.chatHelpers.isEmpty {
            Section(VyronModelRankingText.chatHelpers) {
                ForEach(ranking.chatHelpers) { local in
                    modelChoice(local, title: local.name)
                }
            }
        }
        if !ranking.otherModels.isEmpty {
            Section(VyronModelRankingText.otherModels) {
                ForEach(ranking.otherModels) { local in
                    modelChoice(local, title: VyronModelRankingText.unratedChoice(local.name))
                }
            }
        }
    }

    private func modelChoice(_ local: LocalModel, title: String) -> some View {
        Toggle(isOn: Binding(
            get: { model.modelSelection.isSelectedModel(local.name) },
            set: { selected in
                guard selected else { return }
                model.useLocalModel(
                    local.name,
                    forChat: ModelCatalog.descriptor(for: local.name)?.role == .helper
                )
            }
        )) {
            Text(verbatim: title)
        }
        .disabled(
            ModelCatalog.descriptor(for: local.name)?.role == .helper
                && !model.isConversationModeCompatible(.chat)
        )
    }

    private var connectionChoices: some View {
        Group {
            Button {
                Task { await model.activateConnection(nil) }
            } label: {
                if model.modelSelection.isBuiltinConnection {
                    Label(VyronWorkspaceText.thisMac, systemImage: VyronSymbols.checkmark)
                } else {
                    Text(VyronWorkspaceText.thisMac)
                }
            }
            ForEach(model.modelSelection.connectionProfiles) { profile in
                Button {
                    Task { await model.activateConnection(profile.id) }
                } label: {
                    if model.modelSelection.activeConnectionID == profile.id {
                        Label(profile.name, systemImage: VyronSymbols.checkmark)
                    } else {
                        Text(verbatim: profile.name)
                    }
                }
            }
        }
    }

}
