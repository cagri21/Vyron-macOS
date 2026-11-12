import Foundation

enum VyronEstimatedBalanceInput {
    static func amount(_ text: String, locale: Locale) -> Decimal? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = locale.decimalSeparator ?? "."
        let components = value.components(separatedBy: separator)
        guard !value.isEmpty, components.count <= 2 else { return nil }
        let whole = components[0]
        let fraction = components.count == 2 ? components[1] : ""
        guard !whole.isEmpty || !fraction.isEmpty,
            whole.utf8.allSatisfy({ (48...57).contains($0) }),
            fraction.utf8.allSatisfy({ (48...57).contains($0) }),
            fraction.count <= VyronEstimatedBalanceLimits.maximumFractionDigits
        else { return nil }
        let normalized = (whole.isEmpty ? "0" : whole) + (fraction.isEmpty ? "" : "." + fraction)
        guard let amount = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
            !amount.isNaN, amount >= 0,
            amount <= VyronEstimatedBalanceLimits.maximumEnteredUSD
        else { return nil }
        return amount
    }
}
