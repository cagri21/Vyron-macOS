import Foundation

struct VyronSkillSetupLocations: Sendable {
    let catalogDirectory: URL
    let installationDirectory: URL

    init(catalogDirectory: URL, installationDirectory: URL) {
        self.catalogDirectory = catalogDirectory.standardizedFileURL
        self.installationDirectory = installationDirectory.standardizedFileURL
    }
}
