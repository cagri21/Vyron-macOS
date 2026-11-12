// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronEstimatedBalanceText {
    static var amountPlaceholder: String {
        VyronResourceBundle.string("estimatedBalanceAmountPlaceholder", fallback: "Enter current balance")
    }
    static var checkEstimate: String {
        VyronResourceBundle.string("estimatedBalanceCheckEstimate", fallback: "Estimate needs attention. Open balance details.")
    }
    static var currentBalance: String {
        VyronResourceBundle.string("estimatedBalanceCurrentBalance", fallback: "Current balance (USD)")
    }
    static var explanation: String {
        VyronResourceBundle.string("estimatedBalanceExplanation", fallback: "Enter your OpenAI balance. Vyron subtracts estimated costs for requests made through this connection. Spending elsewhere, top-ups, and expired credits are not tracked. Update the amount to match billing.")
    }
    static var invalidAmount: String {
        VyronResourceBundle.string("estimatedBalanceInvalidAmount", fallback: "Enter 0–1,000,000,000 USD with up to 8 decimal places. Leave out thousands separators.")
    }
    static func remaining(_ p1: String) -> String {
        VyronResourceBundle.format(
            "estimatedBalanceRemaining",
            fallback: "Estimated remaining %@",
            arguments: [p1]
        )
    }
    static var saveBalance: String {
        VyronResourceBundle.string("estimatedBalanceSaveBalance", fallback: "Save balance")
    }
    static var saved: String {
        VyronResourceBundle.string("estimatedBalanceSaved", fallback: "Balance saved.")
    }
    static var setBalance: String {
        VyronResourceBundle.string("estimatedBalanceSetBalance", fallback: "Set balance estimate")
    }
    static var storageError: String {
        VyronResourceBundle.string("estimatedBalanceStorageError", fallback: "The estimate could not be loaded or saved. It may not survive restarting Vyron. Check billing before relying on this amount.")
    }
    static var title: String {
        VyronResourceBundle.string("estimatedBalanceTitle", fallback: "Estimated remaining")
    }
    static var untrackedUsage: String {
        VyronResourceBundle.string("estimatedBalanceUntrackedUsage", fallback: "Some requests could not be priced or did not return usage. The estimate may be too high. Check billing and enter your current balance again.")
    }
    static var updateBalance: String {
        VyronResourceBundle.string("estimatedBalanceUpdateBalance", fallback: "Update balance")
    }
}
