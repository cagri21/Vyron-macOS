import Foundation
import VyronCore

enum VyronConnectionBalancePresentation {
    private static let minimumFractionDigits = 2
    private static let maximumFractionDigits = 8

    static func amount(_ value: VyronConnectionBalanceAmount, locale: Locale) -> String {
        let number = NSDecimalNumber(decimal: value.amount)
        guard number != .notANumber else { return VyronBalanceText.unavailable }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = value.currency
        formatter.currencySymbol = value.currency
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: number) ?? "\(value.currency) \(number.stringValue)"
    }

    static func value(_ snapshot: VyronConnectionBalanceSnapshot, locale: Locale) -> String {
        guard !snapshot.amounts.isEmpty else { return VyronBalanceText.unavailable }
        let amounts = snapshot.amounts.map { amount($0, locale: locale) }.joined(separator: " · ")
        return snapshot.scope == .keyAllowance ? VyronBalanceText.keyAllowanceCompact(amounts) : amounts
    }

    static func badge(_ state: VyronConnectionBalanceState, locale: Locale, isStale: Bool) -> String {
        switch state.phase {
        case .missingKey, .failed(.missingKey): return VyronBalanceText.addAPIKey
        case .failed(.noKeyLimit): return VyronBalanceText.noKeyLimit
        default: break
        }
        if let snapshot = state.snapshot {
            let amount = value(snapshot, locale: locale)
            return isStale ? VyronBalanceText.lastKnown(amount) : amount
        }
        return state.isRefreshing ? VyronBalanceText.updating : VyronBalanceText.unavailable
    }

    static func estimatedAmount(_ amount: Decimal, locale: Locale) -> String {
        self.amount(VyronConnectionBalanceAmount(currency: "USD", amount: amount), locale: locale)
    }

    static func estimatedBadge(_ estimate: VyronEstimatedBalanceState?, locale: Locale) -> String {
        guard let estimate else { return VyronEstimatedBalanceText.setBalance }
        return VyronEstimatedBalanceText.remaining(estimatedAmount(estimate.remainingUSD, locale: locale))
    }

    static func scope(_ scope: VyronConnectionBalanceScope) -> String {
        switch scope {
        case .account: VyronBalanceText.accountBalance
        case .keyAllowance: VyronBalanceText.keyAllowance
        }
    }

    static func explanation(_ state: VyronConnectionBalanceState) -> String {
        switch state.phase {
        case .missingKey: return VyronBalanceText.missingKeyDescription
        case .credentialUnavailable: return VyronBalanceText.credentialUnavailable
        case .failed(let error): return message(error)
        case .idle, .refreshing, .ready: break
        }
        switch state.support {
        case .local: return VyronBalanceText.localDescription
        case .unsupported: return VyronBalanceText.unsupportedDescription
        case .dashboardOnly: return VyronBalanceText.dashboardDescription
        case .deepSeek: return VyronBalanceText.deepSeekDescription
        case .openRouter: return VyronBalanceText.openRouterDescription
        }
    }

    static func message(_ error: VyronConnectionBalanceError) -> String {
        switch error {
        case .unsupported: VyronBalanceText.unsupportedDescription
        case .missingKey: VyronBalanceText.missingKeyDescription
        case .authenticationFailed: VyronBalanceText.authenticationFailed
        case .rateLimited: VyronBalanceText.rateLimited
        case .temporarilyUnavailable: VyronBalanceText.temporarilyUnavailable
        case .noKeyLimit: VyronBalanceText.noKeyLimitDescription
        case .invalidResponse: VyronBalanceText.invalidResponse
        case .connectionFailed: VyronBalanceText.connectionFailed
        }
    }
}
