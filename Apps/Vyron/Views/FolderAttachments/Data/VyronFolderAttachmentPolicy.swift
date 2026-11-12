import Foundation

enum VyronFolderAttachmentPolicy {
    // Match DevelopmentWorkspace's read exclusions without creating its mutable project/history storage.
    private static let excluded: Set<String> = [
        ".git", ".build", ".swiftpm", "node_modules", "vendor", "pods", "carthage", "build", "dist", "deriveddata",
        "__pycache__", "venv", ".venv", "target", "output", "secrets", "credentials"
    ]
    private static let hiddenAllowed: Set<String> = [
        ".gitignore", ".editorconfig", ".swiftlint.yml", ".swiftformat", ".prettierrc"
    ]
    private static let secretExtensions: Set<String> = [
        "env", "pem", "key", "p12", "pfx", "cer", "crt", "der", "mobileprovision", "keystore", "jks", "sqlite",
        "sqlite3", "db", "log"
    ]
    private static let secretNames: Set<String> = [
        "credentials", "credentials.json", "secrets", "secrets.json", "secrets.swift", "auth.json", "tokens.json",
        "token.json", "service-account.json", "google-services.json", "googleservice-info.plist", "id_rsa", "id_ed25519"
    ]

    static func allows(_ component: String) -> Bool {
        let lower = component.lowercased()
        return !component.isEmpty && component != "." && component != ".." && !component.contains("\0")
            && !excluded.contains(lower) && (!component.hasPrefix(".") || hiddenAllowed.contains(lower))
            && !secretNames.contains(lower) && !lower.hasPrefix(".env") && !lower.hasPrefix("credentials.")
            && !lower.hasPrefix("secrets.")
            && !secretExtensions.contains(URL(fileURLWithPath: component).pathExtension.lowercased())
    }

    static func allowsRoot(_ url: URL) -> Bool {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().standardizedFileURL
        return canonical.path != home.path
            && !["/", "/Users", "/System", "/Library", "/Applications", "/private", "/private/tmp"]
                .contains(canonical.path)
            && allows(canonical.lastPathComponent)
            && !canonical.pathComponents.contains { component in
                let lower = component.lowercased()
                return [".ssh", ".aws", ".azure", ".gnupg", "keychains", "credentials", "secrets"].contains(lower)
                    || lower.hasPrefix(".env") || lower.hasPrefix("credentials.") || lower.hasPrefix("secrets.")
            }
    }
}
