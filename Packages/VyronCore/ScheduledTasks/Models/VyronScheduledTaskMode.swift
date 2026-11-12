import Foundation

public enum VyronScheduledTaskMode: String, Codable, CaseIterable, Sendable {
    case agent
    case plan
    case chat
}
