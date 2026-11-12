import Foundation
import VyronModelDomain

enum VyronConnectionBalanceDecimal {
    private static let pattern = #"^-?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#
    private static let locale = Locale(identifier: "en_US_POSIX")

    static func parse(_ text: String) throws -> Decimal {
        guard text.utf8.count <= VyronConnectionBalanceLimits.maximumNumberBytes else {
            throw VyronConnectionBalanceError.invalidResponse
        }
        let original = try canonical(text)
        guard let value = Decimal(string: text, locale: locale), !value.isNaN,
            try original == canonical(NSDecimalNumber(decimal: value).stringValue)
        else { throw VyronConnectionBalanceError.invalidResponse }
        return value
    }

    private static func canonical(_ text: String) throws -> String {
        guard text.range(of: pattern, options: .regularExpression) == text.startIndex..<text.endIndex else {
            throw VyronConnectionBalanceError.invalidResponse
        }
        var unsigned = text
        let negative = unsigned.hasPrefix("-")
        if negative { unsigned.removeFirst() }
        let components = unsigned.split(whereSeparator: { $0 == "e" || $0 == "E" })
        guard let coefficient = components.first else { throw VyronConnectionBalanceError.invalidResponse }
        let exponent: Int
        if components.count == 2 {
            guard let parsed = Int(components[1]), (-512...512).contains(parsed) else {
                throw VyronConnectionBalanceError.invalidResponse
            }
            exponent = parsed
        } else {
            exponent = 0
        }
        let fractionalDigits =
            coefficient.split(separator: ".", omittingEmptySubsequences: false)
            .dropFirst().first?.count ?? 0
        var digits = String(coefficient.filter { $0 != "." })
        while digits.first == "0" { digits.removeFirst() }
        if digits.isEmpty { return "0e0" }
        var trailingZeros = 0
        while digits.last == "0" {
            digits.removeLast()
            trailingZeros += 1
        }
        guard digits.count <= VyronConnectionBalanceLimits.maximumSignificantDigits else {
            throw VyronConnectionBalanceError.invalidResponse
        }
        return (negative ? "-" : "") + digits + "e" + String(exponent - fractionalDigits + trailingZeros)
    }
}
