enum VyronSettingsSection: String, CaseIterable, Identifiable {
    case general
    case voice
    case models
    case billing
    case plugins
    case macControls

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: VyronSettingsText.general
        case .voice: VyronSettingsText.voice
        case .models: VyronSettingsText.models
        case .billing: VyronBillingText.title
        case .plugins: VyronSettingsText.plugins
        case .macControls: VyronSettingsText.macControls
        }
    }

    var symbol: String {
        switch self {
        case .general: VyronSymbols.settings
        case .voice: VyronSymbols.liveVoice
        case .models: VyronSymbols.model
        case .billing: VyronSymbols.balance
        case .plugins: VyronSymbols.plugins
        case .macControls: VyronSymbols.hand
        }
    }

    var searchTerms: [String] {
        switch self {
        case .general:
            [title, VyronLanguageText.title, VyronQueueText.followUpBehavior,
             VyronWorkspaceText.files, VyronWorkspaceText.toggleTerminal]
        case .voice:
            [title, VyronVoiceText.title, VyronVoiceText.voice, VyronVoiceText.startDictation]
        case .models:
            [title, VyronWorkspaceText.manageModels, VyronAppText.settingsAddLocalModel,
             VyronAppText.settingsAutomaticSelection, VyronAppText.settingsOllamaDevelopmentTimeout]
        case .billing:
            [title, VyronBillingText.apiCreditBalance, VyronBillingText.openAI, VyronBalanceText.accountBalance]
        case .plugins:
            [title, VyronPluginText.customName, VyronPluginText.addConnection,
             VyronSkillText.automaticSetupTitle, VyronOfficeText.title]
        case .macControls:
            [title, VyronSidebarText.macControls]
        }
    }
}
