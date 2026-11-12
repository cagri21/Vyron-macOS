enum VyronAppShutdownTiming {
    static let settlementPollLimit = 20
    static let settlementPollInterval: Duration = .milliseconds(100)
    static let runtimeCleanupGracePeriod: Duration = .milliseconds(1_200)
}
