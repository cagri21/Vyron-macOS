enum VyronForegroundRunRoute {
    case foregroundOnly
    case backgroundCapable
    case steerableDevelopment(VyronForegroundSteering)

    var canContinueInBackground: Bool {
        switch self {
        case .foregroundOnly: false
        case .backgroundCapable, .steerableDevelopment: true
        }
    }

    var steering: VyronForegroundSteering? {
        if case .steerableDevelopment(let steering) = self { return steering }
        return nil
    }
}
