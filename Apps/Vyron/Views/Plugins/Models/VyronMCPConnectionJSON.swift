import Foundation
import VyronCore

/// Retains the existing editable MCP JSON transport keys; its fields mirror that compatibility format.
struct VyronMCPConnectionJSON: Codable {
    var name: String
    var type: MCPTransport
    var url: String?
    var command: String?
    var args: [String]?
    var enabled: Bool?
    var permission: MCPPermission?

    init(_ profile: MCPConnectionProfile) {
        name = profile.name; type = profile.transport
        url = type == .http ? profile.endpoint : nil
        command = type == .stdio ? profile.command : nil
        args = type == .stdio ? profile.arguments : nil
        enabled = profile.enabled; permission = profile.permission
    }
    func profile(id: UUID) -> MCPConnectionProfile {
        .init(
            id: id,
            name: name,
            transport: type,
            endpoint: url ?? "",
            command: command ?? "",
            arguments: args ?? [],
            enabled: enabled ?? true,
            permission: permission ?? .readOnly
        )
    }
}
