import SwiftUI
import VyronCore
import VyronRuntime

struct SetupView: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var downloads: VyronModelDownloads
    @ObservedObject private var selection: VyronModelSelectionModel
    @State private var customModelTag = ""
    let showsHeader: Bool

    init(downloads: VyronModelDownloads, selection: VyronModelSelectionModel, showsHeader: Bool = true) {
        self.downloads = downloads
        self.selection = selection
        self.showsHeader = showsHeader
    }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                VyronModelManagerHeader()
                Rectangle().fill(Palette.border).frame(height: VyronSettingsStyle.dividerWidth)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ModelConnectionsView(selection: selection)
                    if selection.isBuiltinConnection {
                        engineSection
                        selectionSection
                    }
                    if !model.canManageModelSelection {
                        notice(
                            VyronAppText.settingsTaskBlocksModels,
                            icon: VyronSymbols.downloadPaused
                        )
                    } else if let transfer = downloads.active {
                        notice(
                            transfer.kind == .ggufImport
                                ? VyronAppText.settingsImportingNotice(transfer.tag)
                                : VyronAppText.settingsDownloadingNotice(transfer.tag),
                            icon: VyronSymbols.download
                        )
                    }
                    if selection.isConnected && !selection.automaticModelSelection && !selection.modelIsAvailable {
                        notice(
                            VyronAppText.settingsSelectedUnavailable(selection.selectedModel),
                            icon: VyronSymbols.warning
                        )
                    }
                    if selection.isBuiltinConnection {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                Eyebrow(text: VyronAppText.settingsCodingOptions)
                                Spacer()
                                Text(VyronAppText.settingsOneDownload)
                                    .font(.system(size: 9)).foregroundStyle(Palette.muted)
                            }
                            ForEach(ModelCatalog.all.filter { $0.role == .coding }) { descriptor in
                                modelCard(descriptor)
                            }
                        }
                        VStack(alignment: .leading, spacing: 11) {
                            Eyebrow(text: VyronAppText.settingsOptionalHelper)
                            ForEach(ModelCatalog.all.filter { $0.role == .helper }) { descriptor in
                                modelCard(descriptor)
                            }
                        }
                        customModelSection
                        if !uncataloguedModels.isEmpty { otherInstalledSection }
                    }
                    if let error = model.errorMessage {
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: VyronSymbols.warning)
                            Text(error).textSelection(.enabled)
                        }.font(.system(size: 11)).foregroundStyle(Palette.warning)
                    }
                    Text(
                        VyronAppText.settingsMemoryExplanation
                    )
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
                }.padding(showsHeader ? VyronSettingsStyle.modelManagerInset : 0)
            }
            if showsHeader {
                Rectangle().fill(Palette.border).frame(height: VyronSettingsStyle.dividerWidth)
                HStack {
                    Label(
                        selection.isBuiltinConnection
                            ? VyronAppText.settingsLocalInference : selection.inferenceLocationLabel,
                        systemImage: selection.activeConnectionIsLocal
                            ? VyronSymbols.computerPreview : VyronSymbols.network
                    ).font(.system(size: 9))
                    Spacer()
                    Text(selection.activeConnectionName).font(.system(size: 9)).lineLimit(1)
                }.foregroundStyle(Palette.muted).padding(.horizontal, 25).padding(.vertical, 14)
            }
        }
        .background(Palette.canvas).foregroundStyle(Palette.text).tint(Palette.controlAccent)
        .task { await model.refreshModels(quiet: true) }
    }

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: VyronSymbols.cpu)
                    .font(.system(size: 23, weight: .ultraLight))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 40, height: 40).background(
                        Palette.accent.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                VStack(alignment: .leading, spacing: 5) {
                    Text(VyronAppText.settingsOllama).font(.system(size: 13, weight: .medium))
                    HStack(spacing: 5) {
                        Circle().fill(selection.isConnected ? Palette.success : Palette.warning).frame(
                            width: 4,
                            height: 4
                        )
                        Text(selection.connectionLabel).font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                }
                Spacer()
                if selection.isStarting || selection.isRefreshing {
                    ProgressView().controlSize(.small)
                } else if selection.isConnected {
                    Button {
                        Task { await model.refreshModels(quiet: true) }
                    } label: {
                        Label(VyronAppText.settingsRefresh, systemImage: VyronSymbols.refresh)
                            .font(.system(size: 11))
                    }.buttonStyle(QuietButtonStyle())
                } else if LocalRuntimeManager.executableURL != nil {
                    Button(VyronAppText.settingsStartEngine) { Task { await model.startEngine() } }
                        .buttonStyle(AccentButtonStyle())
                } else {
                    Link(VyronAppText.settingsGetOllama, destination: URL(string: "https://ollama.com/download/mac")!)
                        .font(.system(size: 11)).foregroundStyle(Palette.accent)
                }
            }
            HStack(spacing: 18) {
                Label(
                    VyronAppText.settingsMemoryAmount(memorySize(model.physicalMemoryBytes)),
                    systemImage: VyronSymbols.memoryChip
                )
                if let free = downloads.availableStorageBytes {
                    Label(VyronAppText.settingsFreeStorage(free.fileSizeLabel), systemImage: VyronSymbols.internalDrive)
                }
            }.font(.system(size: 9)).foregroundStyle(Palette.muted)
            if !selection.isConnected {
                Text(
                    LocalRuntimeManager.executableURL == nil
                        ? VyronAppText.settingsInstallOllama
                        : VyronAppText.settingsStartEngineHint
                )
                .font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(3)
                if LocalRuntimeManager.executableURL == nil {
                    Button(VyronAppText.settingsCheckAgain) { Task { await model.startEngine() } }
                        .font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(Palette.accent)
                }
            }
        }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private var selectionSection: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: VyronSymbols.sparkles)
                .font(.system(size: 17))
                .foregroundStyle(Palette.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(VyronAppText.settingsAutomaticSelection).font(.system(size: 12, weight: .medium))
                Text(
                    VyronAppText.settingsAutomaticDescription
                )
                .font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(3)
                Text(VyronModelRankingText.basis)
                    .font(VyronWorkspaceStyle.captionFont).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            if selection.automaticModelSelection {
                badge(VyronAppText.settingsSelected, color: Palette.accent)
            } else {
                Button(VyronAppText.settingsUseAuto) { model.useAutomaticModels() }
                    .font(.system(size: 11, weight: .medium)).buttonStyle(.plain).foregroundStyle(Palette.accent)
                    .disabled(!model.canManageModelSelection)
            }
        }.padding(15).background(Palette.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.accent.opacity(0.16)))
    }

    private func modelCard(_ descriptor: ModelDescriptor) -> some View {
        let installed = selection.installedModel(for: descriptor)
        let selected = installed.map { selection.isSelectedModel($0.name) } ?? false
        let heavy = descriptor.role == .coding && !descriptor.isAutomaticCodingCandidate
        let active = downloads.active?.tag == descriptor.tag
        let paused = downloads.pausedTags.contains(descriptor.tag)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 9) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(descriptor.displayName).font(.system(size: 15, weight: .medium))
                    Text(VyronModelDescription.summary(descriptor))
                        .font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(3)
                    if let installed, let score = model.modelRanking.score(for: installed.name) {
                        VyronModelScoreLabel(score: score)
                    }
                }
                Spacer(minLength: 0)
                if selected {
                    badge(VyronAppText.settingsSelected, color: Palette.accent)
                } else if heavy {
                    badge(VyronAppText.settingsManualOnly, color: Palette.warning)
                } else if descriptor.tag == ModelCatalog.recommendedCodingTag {
                    badge(VyronAppText.settingsRecommended, color: Palette.accent)
                } else if descriptor.role == .helper {
                    badge(VyronAppText.settingsChatHelper, color: Palette.muted)
                }
            }
            HStack(spacing: 13) {
                Label(
                    installed.map { VyronAppText.settingsOnDisk($0.size.fileSizeLabel) }
                        ?? VyronAppText.settingsDownloadSize(
                            descriptor.downloadSizeGB.formatted(.number.precision(.fractionLength(0...1)))
                        ),
                    systemImage: installed == nil ? VyronSymbols.download : VyronSymbols.internalDrive
                )
                if let quantization = installed?.quantization { Text(quantization).fontDesign(.monospaced) }
                Text(VyronAppText.settingsSuggestedContext(descriptor.recommendedContextTokens / 1_024))
                    .fontDesign(.monospaced)
            }.font(.system(size: 9)).foregroundStyle(Palette.muted)
            Text(installed?.name ?? descriptor.tag).font(.system(size: 9, design: .monospaced)).foregroundStyle(
                Palette.muted
            )
            Text(VyronModelDescription.memoryNote(descriptor)).font(.system(size: 10)).foregroundStyle(
                heavy ? Palette.warning.opacity(0.9) : Palette.muted
            ).lineSpacing(3)
            Rectangle().fill(Palette.border).frame(height: 1)
            if active {
                downloadProgress(tag: descriptor.tag)
            } else {
                HStack(spacing: 9) {
                    Link(VyronAppText.settingsModelDetails, destination: descriptor.documentationURL)
                        .font(.system(size: 9)).foregroundStyle(Palette.muted)
                    Spacer()
                    if let installed {
                        if selected {
                            Label(VyronAppText.settingsInUse, systemImage: VyronSymbols.selected)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.accent)
                        } else {
                            Button(
                                descriptor.role == .helper
                                    ? VyronAppText.settingsUseForChat : VyronAppText.settingsUseModel
                            ) {
                                model.useLocalModel(installed.name, forChat: descriptor.role == .helper)
                            }.buttonStyle(AccentButtonStyle()).disabled(!model.canManageModelSelection)
                        }
                    } else {
                        if paused {
                            Text(VyronAppText.settingsPaused).font(.system(size: 9)).foregroundStyle(Palette.muted)
                        }
                        Button(paused ? VyronAppText.settingsResume : VyronAppText.settingsDownload) {
                            model.downloadModel(descriptor.tag)
                        }
                        .buttonStyle(AccentButtonStyle())
                        .disabled(!selection.isConnected || downloads.isActive || !model.canManageModelSelection)
                        .opacity(
                            !selection.isConnected || downloads.isActive || !model.canManageModelSelection ? 0.5 : 1
                        )
                    }
                }
            }
        }
        .padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(
                selected ? Palette.accent.opacity(0.4) : heavy ? Palette.warning.opacity(0.2) : Palette.border
            )
        )
    }

    private func downloadProgress(tag: String) -> some View {
        VyronModelDownloadProgress(
            progress: downloads.progressByTag[tag],
            isImport: downloads.active?.kind == .ggufImport
        ) {
            model.cancelDownload()
        }
    }

    private var customModelSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Eyebrow(text: VyronAppText.settingsAddLocalModel)
            Text(
                VyronAppText.settingsOllamaTagHint
            )
            .font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(3)
            HStack(spacing: 9) {
                TextField(VyronAppText.settingsOllamaTagPlaceholder, text: $customModelTag)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                Button(VyronAppText.settingsDownload) { model.downloadModel(customModelTag) }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(
                        customModelTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selection.isConnected
                            || downloads.isActive || !model.canManageModelSelection
                    )
            }
            if let tag = downloads.active?.tag, isCustomDownloadTag(tag) {
                Text(tag).font(.system(size: 10, weight: .medium, design: .monospaced))
                downloadProgress(tag: tag)
            }
            ForEach(downloads.pausedTags.filter { isCustomDownloadTag($0) }.sorted(), id: \.self) { tag in
                HStack {
                    Text(tag).font(.system(size: 10, design: .monospaced)).lineLimit(1)
                    Spacer()
                    Button(VyronAppText.settingsResume) { model.downloadModel(tag) }
                        .font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(Palette.accent)
                        .disabled(!selection.isConnected || downloads.isActive || !model.canManageModelSelection)
                }
            }
        }
    }

    private var otherInstalledSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: VyronAppText.settingsOtherModels)
            ForEach(uncataloguedModels) { local in
                HStack(spacing: 9) {
                    Image(systemName: VyronSymbols.modelSource).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(local.name).font(.system(size: 11, weight: .medium, design: .monospaced))
                        Text(
                            [local.size.fileSizeLabel, local.parameterSize, local.quantization].compactMap { $0 }
                                .joined(separator: " · ")
                        )
                        .font(.system(size: 9)).foregroundStyle(Palette.muted)
                        VyronModelScoreLabel(score: model.modelRanking.score(for: local.name))
                    }
                    Spacer()
                    if selection.isSelectedModel(local.name) {
                        badge(VyronAppText.settingsSelected, color: Palette.accent)
                    } else {
                        Button(VyronAppText.settingsUseModel) { model.useLocalModel(local.name) }
                            .font(.system(size: 11, weight: .medium)).buttonStyle(.plain).foregroundStyle(
                                Palette.accent
                            )
                            .disabled(!model.canManageModelSelection)
                    }
                }.padding(.vertical, 4)
            }
        }
    }

    private var uncataloguedModels: [LocalModel] {
        model.modelRanking.allModels.filter { ModelCatalog.descriptor(for: $0.name) == nil }
    }

    private func isCustomDownloadTag(_ tag: String) -> Bool {
        ModelCatalog.descriptor(for: tag)?.tag != tag
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 8, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
    }

    private func notice(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(3)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.raised.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func memorySize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}
