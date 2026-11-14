import SwiftUI
import VyronCore

struct VyronModelConnectionEditor: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var profile: ModelConnectionProfile
    @State private var settings: VyronModelSettingsDraft
    @State private var showsCustomizedSettings: Bool
    @State private var apiKey = ""
    @State private var discoveredModels: [LocalModel] = []
    @State private var precision = ""
    @State private var busy = false
    @State private var error: String?
    @State private var testResult: String?
    @State private var task: Task<Void, Never>?
    @State private var operationID = UUID()

    init(profile: ModelConnectionProfile) {
        _profile = State(initialValue: profile)
        _settings = State(initialValue: VyronModelSettingsDraft(profile.settings))
        _showsCustomizedSettings = State(initialValue: profile.settings != ModelSettings())
    }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(VyronAppText.settingsModelConnection).font(.system(size: 21, weight: .medium))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: VyronSymbols.close)
                }
                .buttonStyle(QuietButtonStyle()).help(VyronAppText.settingsCloseConnection)
            }.padding(22)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    connectionFields.disabled(busy)
                    modelFields.disabled(busy)
                    VyronModelFeatureNotice(report: featureReport)
                    Divider()
                    DisclosureGroup(VyronAppText.settingsOptionalSettings, isExpanded: $showsCustomizedSettings) {
                        VyronModelSettingsFields(
                            draft: $settings,
                            thinkingSupport: thinkingSupport,
                            profile: profile
                        )
                        .padding(.top, 12)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .disabled(busy)
                    Text(VyronAppText.settingsSaveTestHint)
                        .font(.system(size: 10)).foregroundStyle(palette.muted)
                    if let error {
                        Label(error, systemImage: VyronSymbols.warning)
                            .font(.system(size: 11)).foregroundStyle(palette.warning).textSelection(.enabled)
                    }
                    if let testResult {
                        Label(testResult, systemImage: VyronSymbols.checkCircle)
                            .font(.system(size: 11)).foregroundStyle(palette.success).textSelection(.enabled)
                    }
                }.padding(22)
            }
            Divider()
            HStack(spacing: 10) {
                if busy { ProgressView().controlSize(.small) }
                Button(VyronAppText.settingsTestResponse) { test() }
                    .buttonStyle(QuietButtonStyle()).disabled(
                        !canOperate || profile.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                Spacer()
                Button(VyronAppText.settingsCancel) { dismiss() }.buttonStyle(QuietButtonStyle())
                Button(VyronAppText.settingsSaveUse) { save() }.buttonStyle(AccentButtonStyle())
                    .disabled(
                        !canOperate || profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || profile.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }.padding(18)
        }
        .frame(width: 570, height: 700)
        .background(palette.canvas).foregroundStyle(palette.text).tint(palette.controlAccent)
        .onAppear {
            do { apiKey = try model.savedAPIKey(for: profile.id) } catch { self.error = error.localizedDescription }
        }
        .onChange(of: profile.kind) { _, kind in
            if kind == .anthropic {
                if profile.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    profile.endpoint = VyronClaudeConnectionPreset.endpoint
                }
                if profile.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    profile.selectedModel = VyronClaudeConnectionPreset.defaultModel
                }
            }
        }
        .onChange(of: endpointFingerprint) { _, _ in
            cancelTask()
            model.invalidateModelFeatureVerification(for: profile.id)
            discoveredModels = []
            precision = ""
            error = nil
            testResult = nil
            reconcileProviderThinking()
        }
        .onChange(of: profile.selectedModel) { _, _ in
            reconcileProviderThinking()
            testResult = nil
        }
        .onChange(of: settings) { _, _ in
            // Fields are disabled during an operation. Capability discovery may
            // reconcile the thinking choice without invalidating its own snapshot.
            guard !busy else { return }
            cancelTask(); testResult = nil
        }
        .onDisappear { cancelTask() }
    }

    private var connectionFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeledField(
                VyronAppText.settingsConnectionName,
                placeholder: VyronAppText.settingsMyModelServer,
                text: $profile.name
            )
            Picker(VyronAppText.settingsServerType, selection: $profile.kind) {
                Text(VyronAppText.settingsOllama).tag(ModelProviderKind.ollama)
                Text(VyronAppText.settingsCompatibleAPI).tag(ModelProviderKind.openAICompatible)
                Text(verbatim: ModelProviderKind.anthropic.displayName).tag(ModelProviderKind.anthropic)
            }.font(.system(size: 11))
            labeledField(
                VyronAppText.settingsServerURL,
                placeholder: endpointPlaceholder,
                text: $profile.endpoint
            )
            VStack(alignment: .leading, spacing: 6) {
                Text(apiKeyTitle).font(.system(size: 11))
                SecureField(VyronAppText.settingsKeychainPlaceholder, text: $apiKey)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11))
                    .accessibilityLabel(apiKeyTitle)
            }
            Text(apiKeyPrivacy).font(.system(size: 10)).foregroundStyle(palette.muted).lineSpacing(3)
        }
    }

    private var endpointPlaceholder: String {
        switch profile.kind {
        case .ollama: "http://127.0.0.1:11434"
        case .openAICompatible: "https://example.com/v1"
        case .anthropic: VyronClaudeConnectionPreset.endpoint
        }
    }

    private var apiKeyTitle: String {
        if isClaude { return VyronAppText.settingsClaudeAPIKey }
        if isDeepSeek { return VyronAppText.settingsDeepSeekAPIKey }
        return VyronAppText.settingsOptionalAPIKey
    }

    private var apiKeyPrivacy: String {
        if isClaude { return VyronAppText.settingsClaudePrivacy }
        if isDeepSeek { return VyronAppText.settingsDeepSeekPrivacy }
        return VyronAppText.settingsServerPrivacy
    }

    private var modelFields: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Eyebrow(text: VyronAppText.settingsModelPrecision)
                Spacer()
                Button(VyronAppText.settingsDiscoverModels) { discoverModels() }
                    .buttonStyle(QuietButtonStyle()).font(.system(size: 11))
                    .disabled(!canOperate || profile.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if isDeepSeek, discoveredModels.isEmpty {
                Picker(VyronAppText.settingsAvailableModel, selection: $profile.selectedModel) {
                    if !VyronDeepSeekRoute.models.contains(profile.selectedModel) {
                        Text(verbatim: profile.selectedModel).tag(profile.selectedModel)
                    }
                    ForEach(VyronDeepSeekRoute.models, id: \.self) { name in
                        Text(verbatim: name).tag(name)
                    }
                }
                .font(.system(size: 11))
            }
            if !discoveredModels.isEmpty {
                if !precisions.isEmpty {
                    Picker(VyronAppText.settingsPrecision, selection: $precision) {
                        Text(VyronAppText.settingsAllAvailable).tag("")
                        ForEach(precisions, id: \.self) { Text(VyronModelPrecisionLabel.text($0)).tag($0) }
                    }.font(.system(size: 11))
                        .onChange(of: precision) { _, _ in
                            if !filteredModels.contains(where: { $0.name == profile.selectedModel }) {
                                profile.selectedModel = filteredModels.first?.name ?? ""
                            }
                        }
                }
                Picker(VyronAppText.settingsAvailableModel, selection: $profile.selectedModel) {
                    if !filteredModels.contains(where: { $0.name == profile.selectedModel }) {
                        Text(profile.selectedModel.isEmpty ? VyronAppText.settingsChooseModel : profile.selectedModel)
                            .tag(profile.selectedModel)
                    }
                    ForEach(filteredModels) { local in
                        Text(local.name).tag(local.name)
                    }
                }.font(.system(size: 11))
                if let local = discoveredModels.first(where: { $0.name == profile.selectedModel }) {
                    Text(modelDetails(local)).font(.system(size: 10)).foregroundStyle(palette.muted)
                }
            }
            labeledField(
                VyronAppText.settingsModelID,
                placeholder: VyronAppText.settingsExactModelID,
                text: $profile.selectedModel
            )
            Text(
                precisions.isEmpty
                    ? VyronAppText.settingsManualModelHint
                    : VyronAppText.settingsPrecisionVariantHint
            )
            .font(.system(size: 10)).foregroundStyle(palette.muted).lineSpacing(3)
        }
    }

    private var featureReport: VyronModelFeatureReport {
        let local = discoveredModels.first { $0.name == profile.selectedModel }
        do {
            return model.modelFeatureReport(for: try snapshot(), discoveredModel: local)
        } catch {
            // Invalid input must not reuse a successful check for different settings.
            // Keep the metadata-based notice available while the user fixes the draft.
            return VyronModelFeaturePolicy.assess(
                VyronModelFeatureContext(
                    connection: profile,
                    model: local ?? LocalModel(name: profile.selectedModel, size: 0)
                )
            )
        }
    }

    private var thinkingSupport: VyronModelThinkingSupport {
        model.modelThinkingSupport(
            for: profile,
            discoveredModel: discoveredModels.first { $0.name == profile.selectedModel }
        )
    }

    private var endpointFingerprint: String { "\(profile.kind.rawValue)\u{0}\(profile.endpoint)\u{0}\(apiKey)" }
    private var isDeepSeek: Bool { VyronDeepSeekRoute.matches(profile) }
    private var isClaude: Bool { profile.kind == .anthropic }
    private var canOperate: Bool {
        !busy && model.canManageModelSelection && !model.modelDownloads.isActive
            && !model.modelSelection.connectionOperationInProgress
            && (!(isDeepSeek || isClaude) || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    private var precisions: [String] { Array(Set(discoveredModels.compactMap(\.quantization))).sorted() }
    private var filteredModels: [LocalModel] {
        precision.isEmpty ? discoveredModels : discoveredModels.filter { $0.quantization == precision }
    }

    private func reconcileProviderThinking() {
        settings.reconcileThinking(with: thinkingSupport)
        if isDeepSeek, thinkingSupport == .unverified {
            settings.thinking = .automatic
        }
    }

    private func labeledField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11))
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder).font(.system(size: 11))
        }
    }

    private func modelDetails(_ local: LocalModel) -> String {
        var parts = [local.parameterSize, local.quantization].compactMap { $0 }
        if local.size > 0 { parts.append(VyronAppText.settingsWeightSize(local.size.fileSizeLabel)) }
        if local.capabilities?.contains("tools") == true { parts.append(VyronAppText.settingsAgentToolsAdvertised) }
        return parts.isEmpty ? VyronAppText.settingsMissingServerDetails : parts.joined(separator: " · ")
    }

    private func snapshot() throws -> ModelConnectionProfile {
        var value = profile
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.name.isEmpty { value.name = VyronAppText.settingsNewConnection }
        value.endpoint = value.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        value.selectedModel = value.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        value.settings = try settings.settings(thinkingSupport: thinkingSupport, includesSampling: !isClaude)
        return try value.validated()
    }

    private func discoverModels() {
        perform { value, key in
            let found = try await model.discoverConnectionModels(profile: value, apiKey: key)
            try Task.checkCancellation()
            discoveredModels = found
            precision = ""
            if !found.contains(where: { $0.name == profile.selectedModel }), profile.selectedModel.isEmpty {
                profile.selectedModel = found.first?.name ?? ""
            }
            if found.isEmpty { error = VyronAppText.settingsNoModelsFromServer }
        }
    }

    private func test() {
        perform { value, key in
            let result = try await model.testConnection(profile: value, apiKey: key)
            try Task.checkCancellation()
            testResult = result
        }
    }

    private func save() {
        perform { value, key in
            try await model.saveConnection(value, apiKey: key)
            try Task.checkCancellation()
            if model.modelSelection.activeConnectionID != value.id { await model.activateConnection(value.id) }
            try Task.checkCancellation()
            if model.modelSelection.activeConnectionID == value.id {
                dismiss()
            } else {
                error = model.modelSelection.connectionError ?? VyronAppText.settingsConnectionSavedUnavailable
            }
        }
    }

    private func perform(_ operation: @escaping @MainActor (ModelConnectionProfile, String) async throws -> Void) {
        guard canOperate else { return }
        do {
            let value = try snapshot()
            let key = apiKey
            cancelTask()
            let requestID = UUID()
            operationID = requestID
            busy = true
            error = nil
            testResult = nil
            task = Task { @MainActor in
                defer { if operationID == requestID { busy = false; task = nil } }
                do {
                    try await operation(value, key)
                } catch {
                    guard operationID == requestID, !Task.isCancelled else { return }
                    self.error = error.localizedDescription
                }
            }
        } catch {
            showsCustomizedSettings = true
            self.error = error.localizedDescription
        }
    }

    private func cancelTask() {
        operationID = UUID()
        task?.cancel()
        task = nil
        busy = false
    }
}
