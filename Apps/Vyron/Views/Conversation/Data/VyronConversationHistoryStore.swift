import Foundation

struct VyronConversationHistoryStore: Sendable {
    let historyURL: URL

    var directory: URL { historyURL.deletingLastPathComponent() }

    func load() throws -> [Conversation] {
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        guard files.fileExists(atPath: historyURL.path) else { return [] }

        let data = try Data(contentsOf: historyURL)
        return try JSONDecoder().decode([Conversation].self, from: data)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ conversations: [Conversation]) throws {
        let data = try JSONEncoder().encode(conversations)
        try data.write(to: historyURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
    }

    func createRecoveryCopyIfPresent() throws -> Bool {
        let files = FileManager.default
        guard files.fileExists(atPath: historyURL.path) else { return false }

        let backupURL = directory.appendingPathComponent("conversations-recovery-\(UUID().uuidString).json")
        try files.copyItem(at: historyURL, to: backupURL)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        return true
    }
}
