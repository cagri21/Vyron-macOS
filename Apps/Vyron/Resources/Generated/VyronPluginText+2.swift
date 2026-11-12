// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

extension VyronPluginText {
    static var editorConnection: String {
        VyronResourceBundle.string("pluginsEditorConnection", fallback: "Connection")
    }
    static var editorConnectionJSON: String {
        VyronResourceBundle.string("pluginsEditorConnectionJSON", fallback: "Connection JSON")
    }
    static var editorEndpointPlaceholder: String {
        VyronResourceBundle.string("pluginsEditorEndpointPlaceholder", fallback: "https://server.example/mcp")
    }
    static var editorEnvironmentJSON: String {
        VyronResourceBundle.string("pluginsEditorEnvironmentJSON", fallback: "Local command environment (JSON)")
    }
    static var editorExecutable: String {
        VyronResourceBundle.string("pluginsEditorExecutable", fallback: "Executable")
    }
    static var editorExecutablePlaceholder: String {
        VyronResourceBundle.string("pluginsEditorExecutablePlaceholder", fallback: "/absolute/path/to/server")
    }
    static var editorHeadersJSON: String {
        VyronResourceBundle.string("pluginsEditorHeadersJSON", fallback: "HTTP headers (JSON)")
    }
    static var editorInvalidForm: String {
        VyronResourceBundle.string("pluginsEditorInvalidForm", fallback: "Fix the connection JSON before switching to the form.")
    }
    static var editorInvalidJSON: String {
        VyronResourceBundle.string("pluginsEditorInvalidJSON", fallback: "Check the JSON syntax. Credential fields must be JSON objects with text values.")
    }
    static var editorJSONHint: String {
        VyronResourceBundle.string("pluginsEditorJSONHint", fallback: "Use type http or stdio, with url or command and args. Keep tokens in the credential fields below.")
    }
    static var editorJSONMode: String {
        VyronResourceBundle.string("pluginsEditorJSONMode", fallback: "Write configuration as JSON")
    }
    static var editorName: String {
        VyronResourceBundle.string("pluginsEditorName", fallback: "Name")
    }
    static var editorOptional: String {
        VyronResourceBundle.string("pluginsEditorOptional", fallback: "Optional")
    }
    static var editorParametersJSON: String {
        VyronResourceBundle.string("pluginsEditorParametersJSON", fallback: "URL parameters (JSON)")
    }
    static var editorPermissionsHint: String {
        VyronResourceBundle.string("pluginsEditorPermissionsHint", fallback: "Read only exposes tools the server identifies as read-only. Ask before changes also exposes write tools in Agent, with a review of each call. Plan never receives write tools.")
    }
    static var editorSave: String {
        VyronResourceBundle.string("pluginsEditorSave", fallback: "Save connection")
    }
    static var editorServerChanged: String {
        VyronResourceBundle.string("pluginsEditorServerChanged", fallback: "The server changed. Previous credentials were cleared; enter credentials for this server below.")
    }
    static var editorTitle: String {
        VyronResourceBundle.string("pluginsEditorTitle", fallback: "Edit MCP connection")
    }
    static var editorTokenURLHint: String {
        VyronResourceBundle.string("pluginsEditorTokenURLHint", fallback: "You can paste a Penpot URL containing a token. Its URL parameters are moved to Keychain when saved.")
    }
    static var editorToolAccess: String {
        VyronResourceBundle.string("pluginsEditorToolAccess", fallback: "Tool access")
    }
    static var editorTransportHTTP: String {
        VyronResourceBundle.string("pluginsEditorTransportHTTP", fallback: "Streamable HTTP")
    }
    static var editorTransportStdio: String {
        VyronResourceBundle.string("pluginsEditorTransportStdio", fallback: "Local command (stdio)")
    }
    static var editorUnavailableJSON: String {
        VyronResourceBundle.string("pluginsEditorUnavailableJSON", fallback: "The configuration could not be displayed.")
    }
    static var emptyBody: String {
        VyronResourceBundle.string("pluginsEmptyBody", fallback: "Add Penpot or connect a server by URL or local command.")
    }
    static var emptyTitle: String {
        VyronResourceBundle.string("pluginsEmptyTitle", fallback: "Connect your first plugin")
    }
    static var enable: String {
        VyronResourceBundle.string("pluginsEnable", fallback: "Enable plugin")
    }
    static var enabled: String {
        VyronResourceBundle.string("pluginsEnabled", fallback: "Enabled")
    }
    static var importPenpot: String {
        VyronResourceBundle.string("pluginsImportPenpot", fallback: "Import existing Penpot…")
    }
    static var installed: String {
        VyronResourceBundle.string("pluginsInstalled", fallback: "Installed")
    }
    static var managedNote: String {
        VyronResourceBundle.string("pluginsManagedNote", fallback: "Connections and credentials are managed on this Mac.")
    }
    static var noResults: String {
        VyronResourceBundle.string("pluginsNoResults", fallback: "No matching plugins")
    }
    static var noTools: String {
        VyronResourceBundle.string("pluginsNoTools", fallback: "No tools discovered.")
    }
    static var noToolsAccess: String {
        VyronResourceBundle.string("pluginsNoToolsAccess", fallback: "Tools require review in Agent mode.")
    }
    static var penpotDocs: String {
        VyronResourceBundle.string("pluginsPenpotDocs", fallback: "Penpot setup instructions")
    }
    static var penpotHelp: String {
        VyronResourceBundle.string("pluginsPenpotHelp", fallback: "Open your design file in Penpot and choose MCP → Connect.")
    }
}
