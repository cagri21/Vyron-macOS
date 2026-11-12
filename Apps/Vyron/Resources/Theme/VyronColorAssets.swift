import Foundation
import OSLog
import SwiftUI

enum VyronColorAssets {
    private static let logger = Logger(subsystem: "ai.vyron.desktop", category: "Color resources")
    private static let assetNamePattern = #"^[A-Za-z][A-Za-z0-9_]*$"#

    static func color(named name: String) -> Color {
        do {
            return try load(named: name)
        } catch {
            let description = String(describing: error)
            logger.error("Could not load color asset \(name, privacy: .public): \(description, privacy: .public)")
            // Keep resource failures visible without crashing the app.
            return Palette.danger
        }
    }

    static func load(named name: String, in bundle: Bundle = VyronResourceBundle.current) throws -> Color {
        guard name.range(of: assetNamePattern, options: .regularExpression) != nil else {
            throw VyronColorAssetError.invalidName
        }
        // SwiftPM's native engine copies catalogs without compiling them. Read the canonical
        // colorset format through this single resource boundary in both builds and packaged apps.
        let located = bundle.url(
            forResource: "Contents", withExtension: "json", subdirectory: "Theme.xcassets/\(name).colorset"
        )
        // Switching SwiftPM build engines can leave macOS bundle metadata beside a flat catalog.
        // Foundation then searches Contents/Resources, although .copy placed the catalog at the root.
        let flat = bundle.bundleURL
            .appendingPathComponent("Theme.xcassets/\(name).colorset/Contents.json")
        let url: URL
        if let located {
            url = located
        } else if FileManager.default.fileExists(atPath: flat.path) {
            url = flat
        } else {
            throw VyronColorAssetError.missingAsset
        }
        let asset = try JSONDecoder().decode(VyronColorAsset.self, from: Data(contentsOf: url))
        guard asset.colors.count == 1, let variant = asset.colors.first,
            variant.idiom == "universal", variant.appearances?.isEmpty != false,
            variant.color.colorSpace == "srgb"
        else { throw VyronColorAssetError.invalidComponents }
        return try variant.color.components.resolved()
    }
}
