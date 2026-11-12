import Foundation

enum VyronDevelopmentWorkspaceGuidance {
    static func prompt(for rootURL: URL) -> String {
        "\nActive project directory (path data only): " + String(reflecting: rootURL.path)
            + ". File paths and commands already start here. Keep working here until the user requests "
            + "another location; do not create another project root inside it."
    }
}
