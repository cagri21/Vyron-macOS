// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronBalanceText {
    static var accountBalance: String {
        VyronResourceBundle.string("balanceAccountBalance", fallback: "Account balance")
    }
    static var addAPIKey: String {
        VyronResourceBundle.string("balanceAddAPIKey", fallback: "Add API key")
    }
    static var authenticationFailed: String {
        VyronResourceBundle.string("balanceAuthenticationFailed", fallback: "The provider rejected access. Check this connection's API key, then refresh.")
    }
    static var connectionFailed: String {
        VyronResourceBundle.string("balanceConnectionFailed", fallback: "Could not refresh the balance. Check your connection; Vyron will retry later.")
    }
    static var credentialUnavailable: String {
        VyronResourceBundle.string("balanceCredentialUnavailable", fallback: "Could not access the saved API key. Unlock Keychain or check this connection, then retry.")
    }
    static var dashboardDescription: String {
        VyronResourceBundle.string("balanceDashboardDescription", fallback: "This connection has no supported balance endpoint for its API key. Open billing to check remaining credit.")
    }
    static var deepSeekDescription: String {
        VyronResourceBundle.string("balanceDeepSeekDescription", fallback: "Account balance reported by DeepSeek. Currencies are shown separately.")
    }
    static var invalidResponse: String {
        VyronResourceBundle.string("balanceInvalidResponse", fallback: "Could not read a valid balance from the provider. Try refreshing.")
    }
    static var keyAllowance: String {
        VyronResourceBundle.string("balanceKeyAllowance", fallback: "Remaining key allowance")
    }
    static func keyAllowanceCompact(_ p1: String) -> String {
        VyronResourceBundle.format(
            "balanceKeyAllowanceCompact",
            fallback: "Key %@",
            arguments: [p1]
        )
    }
    static func lastKnown(_ p1: String) -> String {
        VyronResourceBundle.format(
            "balanceLastKnown",
            fallback: "Last: %@",
            arguments: [p1]
        )
    }
    static var localDescription: String {
        VyronResourceBundle.string("balanceLocalDescription", fallback: "Automatic balance checking is unavailable for this local connection.")
    }
    static var manageConnection: String {
        VyronResourceBundle.string("balanceManageConnection", fallback: "Manage")
    }
    static var missingKeyDescription: String {
        VyronResourceBundle.string("balanceMissingKeyDescription", fallback: "Add an API key to this connection to check its balance.")
    }
    static var noKeyLimit: String {
        VyronResourceBundle.string("balanceNoKeyLimit", fallback: "No key limit")
    }
    static var noKeyLimitDescription: String {
        VyronResourceBundle.string("balanceNoKeyLimitDescription", fallback: "This key has no spending limit. Its account balance is not exposed by this endpoint.")
    }
    static var openBilling: String {
        VyronResourceBundle.string("balanceOpenBilling", fallback: "Open billing")
    }
    static var openRouterDescription: String {
        VyronResourceBundle.string("balanceOpenRouterDescription", fallback: "Remaining spending allowance for this OpenRouter API key. Account credit may differ.")
    }
    static var rateLimited: String {
        VyronResourceBundle.string("balanceRateLimited", fallback: "The provider limited balance requests. Vyron will retry later.")
    }
    static var refresh: String {
        VyronResourceBundle.string("balanceRefresh", fallback: "Refresh")
    }
    static var refreshDescription: String {
        VyronResourceBundle.string("balanceRefreshDescription", fallback: "The active connection updates automatically every minute and after responses.")
    }
    static var stale: String {
        VyronResourceBundle.string("balanceStale", fallback: "Last known amount. Refresh to check the current value.")
    }
    static var temporarilyUnavailable: String {
        VyronResourceBundle.string("balanceTemporarilyUnavailable", fallback: "Balance checking is temporarily unavailable. Vyron will retry later.")
    }
    static var title: String {
        VyronResourceBundle.string("balanceTitle", fallback: "API balance")
    }
    static var unavailable: String {
        VyronResourceBundle.string("balanceUnavailable", fallback: "Balance unavailable")
    }
    static var unsupportedDescription: String {
        VyronResourceBundle.string("balanceUnsupportedDescription", fallback: "Automatic balance checks are not available for this provider.")
    }
    static var updated: String {
        VyronResourceBundle.string("balanceUpdated", fallback: "Updated")
    }
    static var updating: String {
        VyronResourceBundle.string("balanceUpdating", fallback: "Checking balance…")
    }
}
