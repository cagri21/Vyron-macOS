import SwiftUI
import VyronCore

/// Saved inference connections and public model sources share the model manager,
/// but remain separate: a server URL runs inference, while a source URL installs weights.
struct ModelConnectionsView: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var selection: VyronModelSelectionModel
    @State private var editingProfile: ModelConnectionProfile?

    init(selection: VyronModelSelectionModel) {
        self.selection = selection
    }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Eyebrow(text: VyronAppText.settingsConnections)
                Spacer()
                Button(VyronAppText.settingsAddDeepSeek) {
                    editingProfile = VyronDeepSeekConnectionPreset.makeProfile()
                }
                .font(.system(size: 11)).buttonStyle(QuietButtonStyle())
                .disabled(!canChangeConnection)
                Button(VyronAppText.settingsAddClaude) {
                    editingProfile = VyronClaudeConnectionPreset.makeProfile()
                }
                .font(.system(size: 11)).buttonStyle(QuietButtonStyle())
                .disabled(!canChangeConnection)
                Button(VyronAppText.settingsAddOpenAI) {
                    editingProfile = VyronOpenAIConnectionPreset.makeProfile()
                }
                .font(.system(size: 11)).buttonStyle(QuietButtonStyle())
                .disabled(!canChangeConnection)
                Button {
                    editingProfile = ModelConnectionProfile(name: "", kind: .openAICompatible, endpoint: "")
                } label: {
                    Label(VyronAppText.settingsAddServer, systemImage: VyronSymbols.plus)
                }
                .font(.system(size: 11)).buttonStyle(QuietButtonStyle())
                .disabled(!canChangeConnection)
            }
            VStack(spacing: 0) {
                connectionRow(
                    id: nil,
                    name: VyronAppText.settingsThisMac,
                    detail: VyronAppText.settingsBuiltinDetail,
                    isLocal: true
                )
                ForEach(selection.connectionProfiles) { profile in
                    Rectangle().fill(Palette.border).frame(height: 1)
                    connectionRow(
                        id: profile.id,
                        name: profile.name,
                        detail: [
                            profile.kind == .openAICompatible
                                ? VyronAppText.settingsCompatibleAPI
                                : profile.kind.displayName,
                            isLoopback(profile.endpoint)
                                ? VyronAppText.settingsLocalServer : VyronAppText.settingsRemoteServer,
                            profile.selectedModel
                        ].joined(separator: " · "),
                        isLocal: isLoopback(profile.endpoint),
                        profile: profile
                    )
                }
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            VyronLocalAuthenticationRow(authentication: model.localAuthentication)
            if selection.connectionOperationInProgress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(VyronAppText.settingsCheckingConnection).font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }
            if let message = selection.connectionError {
                Label(message, systemImage: VyronSymbols.warning)
                    .font(.system(size: 11)).foregroundStyle(Palette.warning).textSelection(.enabled)
            } else if let message = selection.connectionStatus {
                Text(message).font(.system(size: 10)).foregroundStyle(Palette.muted).textSelection(.enabled)
            }
            VyronModelFeatureNotice(report: model.modelFeatureReport)
            ModelSourceSection(selection: selection)
            if selection.isBuiltinConnection { VyronBuiltinModelSettingsSection() }
        }
        .sheet(item: $editingProfile) { profile in
            VyronModelConnectionEditor(profile: profile).environmentObject(model)
        }
    }

    private var canChangeConnection: Bool {
        model.canManageModelSelection && !model.modelDownloads.isActive && !selection.connectionOperationInProgress
    }

    private func connectionRow(
        id: UUID?,
        name: String,
        detail: String,
        isLocal: Bool,
        profile: ModelConnectionProfile? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.activateConnection(id) }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: isLocal ? VyronSymbols.computerPreview : VyronSymbols.network)
                        .font(.system(size: 17)).frame(width: 24).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(name).font(.system(size: 12, weight: .medium))
                        Text(detail).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(2)
                    }
                    Spacer(minLength: 6)
                    if selection.activeConnectionID == id {
                        Image(systemName: VyronSymbols.selected).foregroundStyle(Palette.controlAccent)
                            .accessibilityLabel(VyronAppText.settingsActiveConnection)
                    } else {
                        Text(VyronAppText.settingsUse).font(.system(size: 11)).foregroundStyle(Palette.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(!canChangeConnection)
            if let profile {
                let support = VyronConnectionBalancePolicy.support(for: profile)
                if support == .dashboardOnly || support.canFetch {
                    Button(VyronBillingText.title) {
                        model.appNavigation.showSetup = false
                        model.openSettings(.billing)
                    }
                    .buttonStyle(QuietButtonStyle(foreground: Palette.text))
                }
                Button {
                    editingProfile = profile
                } label: {
                    Image(systemName: VyronSymbols.pencil)
                }
                .buttonStyle(QuietButtonStyle())
                .help(VyronAppText.settingsEditConnection(name))
                .accessibilityLabel(VyronAppText.settingsEditConnection(name))
                .disabled(!canChangeConnection)
                Button(role: .destructive) {
                    Task { await model.deleteConnection(profile.id) }
                } label: {
                    Image(systemName: VyronSymbols.trash)
                }
                .buttonStyle(QuietButtonStyle())
                .help(VyronAppText.settingsRemoveConnection(name))
                .accessibilityLabel(VyronAppText.settingsRemoveConnection(name))
                .disabled(!canChangeConnection)
            }
        }
        .padding(14)
    }

    private func isLoopback(_ endpoint: String) -> Bool {
        ["localhost", "127.0.0.1", "::1", "[::1]"].contains(URL(string: endpoint)?.host?.lowercased() ?? "")
    }
}

private struct ModelSourceSection: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var selection: VyronModelSelectionModel
    @State private var sourceURL = ""
    @State private var variants: [ModelSourceVariant] = []
    @State private var selectedVariantID = ""
    @State private var selectedPrecision = ""
    @State private var importName = ""
    @State private var isDiscovering = false
    @State private var discoveryError: String?
    @State private var discoveryTask: Task<Void, Never>?
    @State private var discoveryID = UUID()

    init(selection: VyronModelSelectionModel) {
        self.selection = selection
    }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: VyronAppText.settingsDownloadByURL)
            Text(VyronAppText.settingsSourceHint)
                .font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(3)
            HStack(spacing: 8) {
                TextField(VyronAppText.settingsModelSourceURLPlaceholder, text: $sourceURL)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11))
                    .accessibilityLabel(VyronAppText.settingsSourceURL)
                    .onSubmit { discover() }
                Button(VyronAppText.settingsFindVariants) { discover() }
                    .buttonStyle(AccentButtonStyle()).disabled(
                        sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDiscovering || !canWork
                    )
            }
            if isDiscovering {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(VyronAppText.settingsFindingVariants).font(.system(size: 10)).foregroundStyle(Palette.muted)
                    Spacer()
                    Button(VyronAppText.settingsCancel) { cancelDiscovery() }
                        .buttonStyle(QuietButtonStyle()).font(.system(size: 10))
                }
            }
            if !variants.isEmpty { variantControls }
            if let discoveryError {
                Label(discoveryError, systemImage: VyronSymbols.warning)
                    .font(.system(size: 10)).foregroundStyle(Palette.warning).textSelection(.enabled)
            }
            if !selection.isBuiltinConnection {
                Text(VyronAppText.settingsChooseLocalHint)
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        }
        .padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .onChange(of: sourceURL) { _, _ in
            cancelDiscovery()
            variants = []
            selectedVariantID = ""
            selectedPrecision = ""
            importName = ""
            discoveryError = nil
        }
        .onDisappear { cancelDiscovery() }
    }

    private var variantControls: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(VyronAppText.settingsAvailableVariantCount(variants.count)).font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                Spacer()
                if !precisions.isEmpty {
                    Picker(VyronAppText.settingsPrecision, selection: $selectedPrecision) {
                        Text(VyronAppText.settingsAllAvailable).tag("")
                        ForEach(precisions, id: \.self) { Text(VyronModelPrecisionLabel.text($0)).tag($0) }
                    }
                    .font(.system(size: 11)).frame(maxWidth: 240)
                    .onChange(of: selectedPrecision) { _, _ in selectFirstVariantIfNeeded() }
                }
            }
            Picker(VyronAppText.settingsVariant, selection: $selectedVariantID) {
                ForEach(filteredVariants) { variant in
                    Text(variant.name).tag(variant.id)
                }
            }
            .font(.system(size: 11))
            .onChange(of: selectedVariantID) { _, _ in
                if let selectedVariant { importName = ModelSourceClient.suggestedModelName(for: selectedVariant) }
            }
            if let variant = selectedVariant {
                Text(variantDetails(variant)).font(.system(size: 10, design: .monospaced)).foregroundStyle(
                    Palette.muted
                )
                if variant.ollamaTag == nil {
                    LabeledContent(VyronAppText.settingsLocalModelName) {
                        TextField(VyronAppText.settingsImportModelTagPlaceholder, text: $importName)
                            .textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                    }.font(.system(size: 11))
                }
                Text(VyronAppText.settingsPrecisionHint)
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(3)
                if let bytes = variant.sizeBytes, bytes > model.physicalMemoryBytes {
                    Label(VyronAppText.settingsWeightsExceedMemory, systemImage: VyronSymbols.memoryChip)
                        .font(.system(size: 10)).foregroundStyle(Palette.warning)
                }
                HStack {
                    Spacer()
                    Button(
                        variant.ollamaTag == nil
                            ? VyronAppText.settingsDownloadImport : VyronAppText.settingsDownloadVariant
                    ) {
                        model.importModelVariant(VyronModelImportRequest(variant: variant, name: importName))
                    }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(
                        !canWork || !selection.isBuiltinConnection || !selection.isConnected
                            || (variant.ollamaTag == nil
                                && importName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    )
                }
            }
        }
    }

    private var canWork: Bool {
        model.canManageModelSelection && !model.modelDownloads.isActive && !selection.connectionOperationInProgress
    }
    private var precisions: [String] { Array(Set(variants.compactMap(\.quantization))).sorted() }
    private var filteredVariants: [ModelSourceVariant] {
        selectedPrecision.isEmpty ? variants : variants.filter { $0.quantization == selectedPrecision }
    }
    private var selectedVariant: ModelSourceVariant? { filteredVariants.first { $0.id == selectedVariantID } }

    private func variantDetails(_ variant: ModelSourceVariant) -> String {
        var parts = [variant.parameterSize, variant.quantization].compactMap { $0 }
        if let bytes = variant.sizeBytes { parts.append(VyronAppText.settingsWeightSize(bytes.fileSizeLabel)) }
        if parts.isEmpty { parts.append(VyronAppText.settingsMissingFileDetails) }
        return parts.joined(separator: " · ")
    }

    private func selectFirstVariantIfNeeded() {
        guard !filteredVariants.contains(where: { $0.id == selectedVariantID }) else { return }
        selectedVariantID = filteredVariants.first?.id ?? ""
        if let selectedVariant { importName = ModelSourceClient.suggestedModelName(for: selectedVariant) }
    }

    private func discover() {
        guard canWork, !isDiscovering else { return }
        guard let url = URL(string: sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil
        else {
            discoveryError = VyronAppText.settingsCompleteSourceURL
            return
        }
        cancelDiscovery()
        let requestID = UUID()
        discoveryID = requestID
        isDiscovering = true
        discoveryError = nil
        variants = []
        discoveryTask = Task { @MainActor in
            defer {
                if discoveryID == requestID { isDiscovering = false; discoveryTask = nil }
            }
            do {
                let found = try await ModelSourceClient().discover(url: url)
                try Task.checkCancellation()
                guard discoveryID == requestID else { return }
                variants = found
                selectedPrecision = ""
                selectedVariantID = found.first?.id ?? ""
                if let first = found.first { importName = ModelSourceClient.suggestedModelName(for: first) }
                if found.isEmpty { discoveryError = VyronAppText.settingsNoSupportedVariant }
            } catch {
                guard discoveryID == requestID, !Task.isCancelled else { return }
                discoveryError = error.localizedDescription
            }
        }
    }

    private func cancelDiscovery() {
        discoveryID = UUID()
        discoveryTask?.cancel()
        discoveryTask = nil
        isDiscovering = false
    }
}
