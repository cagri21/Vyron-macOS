import Foundation

public struct VyronChromeBridgeSession: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let extensionID: String
    public let updatedAt: Date

    init(id: UUID, extensionID: String, updatedAt: Date) {
        self.id = id
        self.extensionID = extensionID
        self.updatedAt = updatedAt
    }

    func isLive(now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(updatedAt)
        return (0...VyronChromeBridgePolicy.heartbeatLifetime).contains(age)
            && extensionID.count == 32 && extensionID.allSatisfy { ("a"..."p").contains(String($0)) }
    }
}
