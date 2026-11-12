import Foundation

public enum VyronLocalAuthStatus: Sendable, Equatable {
    case notConfigured
    case connecting
    case connected
    case unavailable
}
