import Foundation

public enum VyronChromeBridgeError: Error, LocalizedError, Sendable, Equatable {
    case invalidPath
    case invalidMessage
    case invalidOrigin
    case unavailable
    case timeout
    case storage

    public var errorDescription: String? {
        switch self {
        case .invalidPath: "The Chrome bridge storage path is not a private, ordinary directory."
        case .invalidMessage: "The Chrome bridge received an invalid or oversized message."
        case .invalidOrigin: "This Chrome extension is not registered for the Vyron native host."
        case .unavailable: "Open Chrome and connect the Vyron extension before using this tool."
        case .timeout: "Chrome did not finish this request before it expired. The request was not retried."
        case .storage: "The Chrome bridge could not safely access its local message storage."
        }
    }
}
