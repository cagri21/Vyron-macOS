enum VyronAutomationBrowserCommand: String, CaseIterable {
    case back
    case forward
    case reload

    var title: String {
        switch self {
        case .back: VyronAppText.automationBack
        case .forward: VyronAppText.automationForward
        case .reload: VyronAppText.automationReload
        }
    }

    var symbol: String {
        switch self {
        case .back: VyronSymbols.browserBack
        case .forward: VyronSymbols.browserForward
        case .reload: VyronSymbols.browserReload
        }
    }
}
