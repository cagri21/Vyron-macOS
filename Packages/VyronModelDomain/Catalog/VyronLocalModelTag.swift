import Foundation

package enum VyronLocalModelTag {
    private static let pattern =
        #"\A[A-Za-z0-9][A-Za-z0-9._-]*(?:/[A-Za-z0-9][A-Za-z0-9._-]*)?(?::[A-Za-z0-9][A-Za-z0-9._-]*)?\z"#

    package static func validate(_ name: String) throws {
        if isCloud(name) { throw LocalAIError.cloudModelNotAllowed }
        guard isValid(name) else { throw LocalAIError.invalidModelName }
    }

    package static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 200, !isCloud(name),
            name.range(of: pattern, options: .regularExpression) != nil
        else { return false }

        let components = name.split(separator: "/")
        // Local selection accepts a model namespace and excludes registry domains.
        return components.count == 1 || !components[0].contains(".")
    }

    private static func isCloud(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized.contains(":cloud") || normalized.contains("-cloud")
    }
}
