enum VyronAutomationManualKey: String, CaseIterable {
    case returnKey = "return"
    case escape
    case tab
    case space
    case upArrow = "up"
    case downArrow = "down"
    case leftArrow = "left"
    case rightArrow = "right"

    var title: String {
        switch self {
        case .returnKey: VyronAppText.automationReturnKey
        case .escape: VyronAppText.automationEscapeKey
        case .tab: VyronAppText.automationTabKey
        case .space: VyronAppText.automationSpaceKey
        case .upArrow: VyronAppText.automationUpKey
        case .downArrow: VyronAppText.automationDownKey
        case .leftArrow: VyronAppText.automationLeftKey
        case .rightArrow: VyronAppText.automationRightKey
        }
    }
}
