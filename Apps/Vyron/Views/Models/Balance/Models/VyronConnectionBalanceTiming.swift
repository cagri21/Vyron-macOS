import Foundation

enum VyronConnectionBalanceTiming {
    static let refreshSeconds: TimeInterval = 60
    static let responseDelaySeconds: TimeInterval = 5
    static let staleSeconds: TimeInterval = 120

    static func retrySeconds(failureCount: Int) -> TimeInterval {
        switch failureCount {
        case ...1: 60
        case 2: 120
        case 3: 240
        default: 300
        }
    }
}
