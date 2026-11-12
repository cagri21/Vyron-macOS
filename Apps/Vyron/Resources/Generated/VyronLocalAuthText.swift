// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronLocalAuthText {
    static var connected: String {
        VyronResourceBundle.string("localAuthConnected", fallback: "Connected")
    }
    static var connecting: String {
        VyronResourceBundle.string("localAuthConnecting", fallback: "Connecting…")
    }
    static var credentialsUnavailable: String {
        VyronResourceBundle.string("localAuthCredentialsUnavailable", fallback: "Could not access device credentials in Keychain. Unlock Keychain and retry.")
    }
    static var description: String {
        VyronResourceBundle.string("localAuthDescription", fallback: "Connects automatically on this Mac. Keys stay in Keychain with an encrypted local backup.")
    }
    static var encryptionKeyMissing: String {
        VyronResourceBundle.string("localAuthEncryptionKeyMissing", fallback: "The existing backup’s encryption key is missing. Saved API keys were preserved.")
    }
    static var integrityFailed: String {
        VyronResourceBundle.string("localAuthIntegrityFailed", fallback: "The encrypted backup could not be verified. Saved API keys were preserved.")
    }
    static var invalidConfiguration: String {
        VyronResourceBundle.string("localAuthInvalidConfiguration", fallback: "Could not read the local authentication settings. Check the setup.")
    }
    static var notConfigured: String {
        VyronResourceBundle.string("localAuthNotConfigured", fallback: "Not configured")
    }
    static var retry: String {
        VyronResourceBundle.string("localAuthRetry", fallback: "Retry")
    }
    static var serviceUnavailable: String {
        VyronResourceBundle.string("localAuthServiceUnavailable", fallback: "Start the local Docker service and retry. Saved model connections remain available.")
    }
    static var title: String {
        VyronResourceBundle.string("localAuthTitle", fallback: "Local authentication")
    }
    static var unauthorized: String {
        VyronResourceBundle.string("localAuthUnauthorized", fallback: "The local service rejected this Mac. Check the local authentication setup.")
    }
    static var unavailable: String {
        VyronResourceBundle.string("localAuthUnavailable", fallback: "Unavailable")
    }
}
