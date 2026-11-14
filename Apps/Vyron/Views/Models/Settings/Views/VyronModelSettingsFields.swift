import SwiftUI
import VyronCore

struct VyronModelSettingsFields: View {
    @Environment(\.locale) private var localizationLocale
    @Binding var draft: VyronModelSettingsDraft
    let thinkingSupport: VyronModelThinkingSupport
    var profile: ModelConnectionProfile?

    private var claudeModelID: String? {
        guard let profile, profile.kind == .anthropic else { return nil }
        return profile.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var deepSeekBudget: VyronDeepSeekModelBudget? {
        profile.flatMap { VyronDeepSeekModelBudget.published(for: $0) }
    }

    private var automaticContextTokens: Int? {
        if let claudeModelID { return VyronClaudeModelBudget.contextTokens(for: claudeModelID) }
        return deepSeekBudget?.contextTokens
    }

    private var contextPlaceholder: String {
        guard let tokens = automaticContextTokens else { return VyronAppText.settingsAutomatic }
        return VyronAppText.settingsAutomaticContextTokens(tokens.formatted(.number.locale(localizationLocale)))
    }

    private var publishedOutputTokenLimit: Int? {
        if let claudeModelID, VyronClaudeModelBudget.hasPublishedLimits(for: claudeModelID) {
            return VyronClaudeModelBudget.maximumOutputTokens(for: claudeModelID)
        }
        return deepSeekBudget?.maximumOutputTokens
    }

    private var thinkingChoices: [VyronModelThinkingChoice] {
        VyronModelThinkingChoice.available(for: thinkingSupport)
    }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: 12) {
            Text(VyronAppText.settingsDefaultsHint)
                .font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(3)
            setting(
                VyronAppText.settingsContextBudget,
                placeholder: contextPlaceholder,
                text: $draft.budget.contextTokens
            )
            if let profile, profile.kind != .ollama {
                Text(VyronAppText.settingsRequestBudgetHint)
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(3)
            }
            setting(
                VyronAppText.settingsMaxResponseTokens,
                placeholder: VyronAppText.settingsAutomatic,
                text: $draft.budget.maxOutputTokens
            )
            if let tokens = publishedOutputTokenLimit {
                Text(VyronAppText.settingsClaudeOutputLimit(tokens.formatted(.number.locale(localizationLocale))))
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(3)
            }
            if profile == nil { ollamaTimeoutField }
            if claudeModelID == nil {
                samplingFields
                thinkingField
            }
        }
        .onChange(of: thinkingSupport, initial: true) { _, support in
            draft.reconcileThinking(with: support)
        }
    }

    private var ollamaTimeoutField: some View {
        let allowed = VyronOllamaDevelopmentTimeout.allowedSeconds
        let defaultSeconds = String(VyronOllamaDevelopmentTimeout.defaultSeconds)
        return Group {
            setting(
                VyronAppText.settingsOllamaDevelopmentTimeout,
                placeholder: defaultSeconds,
                text: $draft.budget.ollamaDevelopmentTimeoutSeconds
            )
            Text(VyronAppText.settingsOllamaDevelopmentTimeoutHint(
                String(allowed.lowerBound), String(allowed.upperBound), defaultSeconds
            ))
            .font(VyronWorkspaceStyle.captionFont)
            .foregroundStyle(Palette.muted)
        }
    }

    private var samplingFields: some View {
        Group {
            setting(
                VyronAppText.settingsTemperature,
                placeholder: VyronAppText.settingsModelDefault,
                text: $draft.sampling.temperature
            )
            setting(
                VyronAppText.settingsTopP,
                placeholder: VyronAppText.settingsModelDefault,
                text: $draft.sampling.topP
            )
        }
    }

    private var thinkingField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(
                VyronAppText.settingsThinking,
                selection: Binding(
                    get: { thinkingChoices.contains(draft.thinking) ? draft.thinking : .automatic },
                    set: { draft.thinking = $0 }
                )
            ) {
                ForEach(thinkingChoices, id: \.self) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .font(.system(size: 11))
            .disabled(thinkingChoices.count == 1)
            Text(VyronAppText.settingsThinkingHint)
                .font(VyronWorkspaceStyle.captionFont)
                .foregroundStyle(Palette.muted)
        }
    }

    private func setting(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Text(label).font(.system(size: 11))
            Spacer(minLength: 12)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced)).frame(width: 170)
                .accessibilityLabel(label)
        }
    }
}
