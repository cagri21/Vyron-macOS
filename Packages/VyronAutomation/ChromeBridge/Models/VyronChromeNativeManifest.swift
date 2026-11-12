import Foundation

/// Keys intentionally match Chrome's native messaging host manifest.
struct VyronChromeNativeManifest: Codable {
    let name: String
    let description: String?
    let path: String
    let type: String
    let allowed_origins: [String]

    init(path: String, origin: String) {
        name = "ai.vyron.chrome"
        description = "Vyron Chrome browser bridge"
        self.path = path
        type = "stdio"
        allowed_origins = [origin]
    }
}
