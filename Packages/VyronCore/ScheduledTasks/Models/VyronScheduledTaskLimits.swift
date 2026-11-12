import VyronModelDomain

public enum VyronScheduledTaskLimits {
    static let taskCount = 100
    public static let titleCharacters = 160
    public static let promptBytes = VyronTaskPromptLimits.maximumUTF8Bytes
    public static let agentPromptCharacters = VyronTaskPromptLimits.maximumCharacters
    static let pathBytes = 4_096
    static let modelBytes = 1_024
    static let detailBytes = 65_536
    static let storeBytes = 4_194_304
}
