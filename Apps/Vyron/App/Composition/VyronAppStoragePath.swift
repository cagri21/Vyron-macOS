enum VyronAppStoragePath: String {
    case localAuthentication = "LocalAuth"
    case conversationHistory = "conversations.json"
    case estimatedBalances = "estimated-balances.json"
    case sidebar = "sidebar.json"
    case notificationReadState = "notification-read.json"
    case modelConnections = "model-connections.json"
    case mcpConnections = "mcp-connections.json"
    case scheduledTasks = "scheduled-tasks.json"

    static let appDataDirectoryName = "VyronAI"
    static let applicationSupportHomePath = "Library/Application Support"

    var isDirectory: Bool { self == .localAuthentication }
}
