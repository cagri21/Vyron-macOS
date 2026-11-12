import Foundation

struct VyronSkillSetupCatalogEntry: Decodable, Sendable {
    let identifier: String
    let aliases: [String]
    let terms: [String]
    let actions: [String]

    var isValid: Bool {
        let bytes = Array(identifier.utf8)
        guard let first = bytes.first, (97...122).contains(first), bytes.count <= 64,
            bytes.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }),
            (1...32).contains(aliases.count), (1...32).contains(terms.count), (1...64).contains(actions.count)
        else { return false }
        return aliases.allSatisfy(Self.isValidAlias)
            && (terms + actions).allSatisfy {
                !$0.isEmpty && $0.count <= 80 && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }

    func matches(_ prompt: String) -> Bool {
        VyronSkillSetupIntent.matches(prompt, entry: self)
    }

    private static func isValidAlias(_ alias: String) -> Bool {
        !alias.isEmpty && alias.utf8.count <= 80 && alias.unicodeScalars.allSatisfy {
            (97...122).contains($0.value) || (48...57).contains($0.value) || "-_.:".unicodeScalars.contains($0)
        }
    }
}
