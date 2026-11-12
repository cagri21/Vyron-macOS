import Foundation
import VyronLocalization
import VyronModelDomain

func validatedModelAPIKey(_ value: String?) throws -> String? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    guard value.utf8.count <= VyronModelCredentialLimits.maximumRequestKeyBytes,
        !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { throw ModelProviderError.invalidSettings(VyronModelDataText.apiKeyUnsupportedCharacters) }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
}
