import Foundation

struct VyronInstalledApplication: Sendable {
    let id: String
    let name: String
    let url: URL

    var application: DesktopApplication {
        DesktopApplication(installedAt: url, name: name, bundleIdentifier: id)
    }
}
