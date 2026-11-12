import Foundation
import VyronCore

enum VyronAgentCatalogPreset {
    static var bundledScriptURL: URL? {
        VyronResourceBundle.current.url(
            forResource: "agent_catalog_mcp",
            withExtension: "py",
            subdirectory: "CodexCatalog"
        )
    }

    static func makeProfile(
        scriptURL: URL? = bundledScriptURL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        projectDirectory: URL? = nil
    ) -> MCPConnectionProfile? {
        guard let scriptURL, scriptURL.isFileURL, homeDirectory.isFileURL,
            projectDirectory?.isFileURL != false
        else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: scriptURL.path, isDirectory: &isDirectory),
            !isDirectory.boolValue, FileManager.default.isReadableFile(atPath: scriptURL.path)
        else { return nil }
        var profile = MCPConnectionProfile(name: VyronPluginText.agentBridgeName)
        profile.transport = .stdio
        profile.command = "python3"
        profile.arguments = ["-I", scriptURL.path, "--home-root", homeDirectory.standardizedFileURL.path]
        if let projectDirectory {
            profile.arguments += ["--project-root", projectDirectory.standardizedFileURL.path]
        }
        profile.permission = .readOnly
        profile.enabled = false
        return profile
    }
}
