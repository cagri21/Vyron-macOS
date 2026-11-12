import Foundation

public enum VyronTaskRecurrence: String, Codable, CaseIterable, Sendable {
    case once
    case daily
    case weekly
}
