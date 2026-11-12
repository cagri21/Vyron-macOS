import Foundation

struct VyronCatalogModelIdentity: Sendable, Hashable {
    let tag: String
    let displayName: String
    let downloadSizeGB: Double
    let documentationURL: URL

    init(tag: String, displayName: String, downloadSizeGB: Double) {
        self.tag = tag
        self.displayName = displayName
        self.downloadSizeGB = downloadSizeGB
        guard let documentationURL = URL(string: "https://ollama.com/library/" + tag) else {
            preconditionFailure("Invalid bundled model catalog tag: \(tag)")
        }
        self.documentationURL = documentationURL
    }
}
