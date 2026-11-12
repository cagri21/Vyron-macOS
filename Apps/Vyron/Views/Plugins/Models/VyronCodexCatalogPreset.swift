import Foundation
import VyronCore

enum VyronCodexCatalogPreset {
    static var bundledScriptURL: URL? {
        VyronResourceBundle.current.url(
            forResource: "codex_catalog_mcp",
            withExtension: "py",
            subdirectory: "CodexCatalog"
        )
    }

    static func makeProfile(scriptURL: URL? = bundledScriptURL) -> MCPConnectionProfile? {
        guard let scriptURL, scriptURL.isFileURL else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: scriptURL.path, isDirectory: &isDirectory),
            !isDirectory.boolValue, FileManager.default.isReadableFile(atPath: scriptURL.path)
        else { return nil }
        var profile = MCPConnectionProfile(name: VyronPluginText.codexName)
        profile.transport = .stdio
        profile.command = "python3"
        profile.arguments = ["-I", scriptURL.path]
        profile.permission = .readOnly
        return profile
    }
}
