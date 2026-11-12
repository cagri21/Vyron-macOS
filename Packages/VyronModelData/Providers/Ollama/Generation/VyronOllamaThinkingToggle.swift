import VyronModelDomain

enum VyronOllamaThinkingToggle {
    case enabled
    case disabled

    init(_ value: Bool) {
        self = value ? .enabled : .disabled
    }

    var value: Bool { self == .enabled }
}
