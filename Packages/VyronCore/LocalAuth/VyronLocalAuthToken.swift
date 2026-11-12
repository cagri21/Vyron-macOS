import Foundation

enum VyronLocalAuthToken {
    static func decode(_ data: Data) throws -> Data {
        guard let raw = String(data: data, encoding: .utf8) else { throw VyronLocalAuthError.invalidConfiguration }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count == VyronLocalAuthLimits.tokenCharacters,
            value.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
            let decoded = Data(base64Encoded: value.replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/") + "="),
            decoded.count == VyronLocalAuthLimits.secretBytes, encode(decoded) == value else {
            throw VyronLocalAuthError.invalidConfiguration
        }
        return decoded
    }

    static func encode(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
