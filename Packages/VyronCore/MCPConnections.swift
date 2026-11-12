import Foundation

public enum MCPTransport: String, Codable, CaseIterable, Identifiable, Sendable {
    case http, stdio
    public var id: String { rawValue }
    public var displayName: String { self == .http ? "Streamable HTTP" : "Local command (stdio)" }
}

public enum MCPPermission: String, Codable, CaseIterable, Identifiable, Sendable {
    case readOnly, askForWrites
    public var id: String { rawValue }
    public var displayName: String { self == .readOnly ? "Read only" : "Ask before changes" }
}

public struct MCPConnectionProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var transport: MCPTransport
    public var endpoint: String
    public var command: String
    public var arguments: [String]
    public var enabled: Bool
    public var permission: MCPPermission

    public init(
        id: UUID = UUID(),
        name: String,
        transport: MCPTransport = .http,
        endpoint: String = "",
        command: String = "",
        arguments: [String] = [],
        enabled: Bool = true,
        permission: MCPPermission = .readOnly
    ) {
        self.id = id; self.name = name; self.transport = transport; self.endpoint = endpoint
        self.command = command; self.arguments = arguments; self.enabled = enabled; self.permission = permission
    }

    public static var penpot: MCPConnectionProfile {
        MCPConnectionProfile(name: "Penpot", endpoint: "http://localhost:4401/mcp", permission: .askForWrites)
    }

    public func validated() throws -> MCPConnectionProfile {
        var copy = self
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !copy.name.isEmpty, copy.name.count <= 120, !copy.name.contains("\0") else {
            throw MCPError.configuration("Give the MCP connection a name of at most 120 characters.")
        }
        switch transport {
        case .http:
            copy.endpoint = try MCPEndpoint.validated(endpoint).absoluteString
            copy.command = ""; copy.arguments = []
        case .stdio:
            copy.command = command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !copy.command.isEmpty, copy.command.utf8.count <= 2_048,
                !copy.command.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                (copy.command.hasPrefix("/") || !copy.command.contains("/")),
                copy.command.hasPrefix("/") || !copy.command.contains(where: \.isWhitespace),
                arguments.count <= 100, arguments.allSatisfy({ $0.utf8.count <= 16_384 && !$0.contains("\0") })
            else {
                throw MCPError.configuration(
                    "Enter an executable name or absolute path. Put each command argument in the arguments list."
                )
            }
            copy.endpoint = ""
        }
        return copy
    }
}

public enum MCPEndpoint {
    /// Query parameters may contain Penpot's userToken. Store the returned parameters in Keychain.
    public static func separateSecrets(
        _ input: String
    ) throws -> (endpoint: String, queryParameters: [String: String]) {
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw MCPError.configuration("Enter a complete MCP server URL.")
        }
        var query: [String: String] = [:]
        for item in parts.queryItems ?? [] {
            guard query[item.name] == nil else {
                throw MCPError.configuration("The MCP URL contains a repeated query parameter.")
            }
            query[item.name] = item.value ?? ""
        }
        parts.query = nil
        guard let url = parts.url else { throw MCPError.configuration("Enter a complete MCP server URL.") }
        return (try validated(url.absoluteString).absoluteString, query)
    }

    public static func validated(_ input: String) throws -> URL {
        guard input.utf8.count <= 4_096,
            let parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
            let host = parts.host?.lowercased(), !host.isEmpty,
            let scheme = parts.scheme?.lowercased(),
            scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)),
            parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
            parts.port == nil || (1...65_535).contains(parts.port!), let url = parts.url
        else {
            throw MCPError.configuration(
                "Use HTTPS for remote MCP servers or HTTP on localhost. Store URL query parameters with the connection credentials."
            )
        }
        return url
    }
}

/// All values in this type belong in Keychain, never in mcp-connections.json or activity logs.
public struct MCPConnectionSecrets: Codable, Equatable, Sendable {
    public var bearerToken: String
    public var headers: [String: String]
    public var environment: [String: String]
    public var queryParameters: [String: String]

    public init(
        bearerToken: String = "",
        headers: [String: String] = [:],
        environment: [String: String] = [:],
        queryParameters: [String: String] = [:]
    ) {
        self.bearerToken = bearerToken; self.headers = headers
        self.environment = environment; self.queryParameters = queryParameters
    }

    public func validated() throws -> MCPConnectionSecrets {
        let reserved = Set([
            "host", "content-length", "content-type", "accept", "mcp-session-id", "mcp-protocol-version",
            "connection", "transfer-encoding"
        ])
        let headerName = CharacterSet(
            charactersIn: "!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        )
        guard bearerToken.utf8.count <= 16_384,
            !bearerToken.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
            headers.count <= 32, Set(headers.keys.map { $0.lowercased() }).count == headers.count,
            headers.allSatisfy({ key, value in
                !key.isEmpty && key.utf8.count <= 128 && key.unicodeScalars.allSatisfy(headerName.contains)
                    && !reserved.contains(key.lowercased()) && value.utf8.count <= 16_384
                    && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            }),
            environment.count <= 64,
            environment.allSatisfy({ key, value in
                !key.isEmpty && key.utf8.count <= 128 && !key.contains("=") && !key.contains("\0")
                    && value.utf8.count <= 16_384 && !value.contains("\0")
            }),
            queryParameters.count <= 32,
            queryParameters.allSatisfy({ key, value in
                !key.isEmpty && key.utf8.count <= 128 && value.utf8.count <= 16_384
                    && !key.contains("\0") && !value.contains("\0")
            })
        else { throw MCPError.configuration("MCP credentials contain invalid values or exceed the size limit.") }
        return self
    }
}

public struct MCPTool: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let description: String?
    public let inputSchema: [String: DevelopmentJSONValue]
    public let annotations: [String: DevelopmentJSONValue]?

    public init(
        name: String,
        description: String? = nil,
        inputSchema: [String: DevelopmentJSONValue] = ["type": .string("object")],
        annotations: [String: DevelopmentJSONValue]? = nil
    ) {
        self.name = name; self.description = description; self.inputSchema = inputSchema;
        self.annotations = annotations
    }

    /// Annotations are hints from the configured server. General code execution always requires review.
    public var isReadOnly: Bool {
        guard annotations?["readOnlyHint"] == .bool(true) else { return false }
        let separated = name.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1_$2", options: .regularExpression)
        let parts = separated.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let mutable = Set([
            "execute", "exec", "run", "eval", "write", "create", "update", "delete", "remove", "import", "export",
            "edit", "set", "mutate"
        ])
        return parts.allSatisfy { !mutable.contains(String($0)) }
    }
}

public struct MCPToolResult: Codable, Equatable, Sendable {
    public let content: [[String: DevelopmentJSONValue]]
    public let structuredContent: DevelopmentJSONValue?
    public let isError: Bool

    public init(
        content: [[String: DevelopmentJSONValue]] = [],
        structuredContent: DevelopmentJSONValue? = nil,
        isError: Bool = false
    ) {
        self.content = content; self.structuredContent = structuredContent; self.isError = isError
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        content = try values.decodeIfPresent([[String: DevelopmentJSONValue]].self, forKey: .content) ?? []
        structuredContent = try values.decodeIfPresent(DevelopmentJSONValue.self, forKey: .structuredContent)
        isError = try values.decodeIfPresent(Bool.self, forKey: .isError) ?? false
    }

    public var readableText: String {
        var pieces = content.compactMap { block -> String? in
            if case .string(let text) = block["text"] { return text }
            if case .object(let resource) = block["resource"], case .string(let text) = resource["text"] {
                return text
            }
            if case .string(let type) = block["type"] { return "[MCP \(type) content]" }
            return nil
        }
        if let structuredContent, let data = try? JSONEncoder().encode(structuredContent),
            let text = String(data: data, encoding: .utf8) {
            pieces.append(text)
        }
        return String(pieces.joined(separator: "\n").prefix(48_000))
    }
}

public enum MCPError: Error, LocalizedError, Sendable, Equatable {
    case configuration(String), transport(String), protocolError(String), server(Int), http(Int), timeout,
        disconnected, busy
    public var errorDescription: String? {
        switch self {
        case .configuration(let message), .transport(let message), .protocolError(let message): message
        case .server(let code):
            "The MCP server returned error \(code). Check the server and its connection to the design file."
        case .http(let status):
            "The MCP server returned HTTP \(status). Check its URL, credentials, and server status."
        case .timeout: "The MCP server did not respond before the request timed out."
        case .disconnected: "The MCP connection is closed. Connect again before using its tools."
        case .busy: "This MCP connection is already handling a request."
        }
    }
}
