import Foundation

enum VyronConnectionBalanceLimits {
    static let responseBytes = 65_536
    static let requestTimeout: TimeInterval = 15
    static let resourceTimeout: TimeInterval = 20
    static let maximumKeyBytes = 8_192
    static let maximumNumberBytes = 128
    static let maximumSignificantDigits = 38
}
