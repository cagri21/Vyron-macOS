import Foundation

private typealias MCPObject = [String: DevelopmentJSONValue]

private final class MCPRejectRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) { completionHandler(nil) }
}

/// A deliberately small MCP client: tools only, without server sampling, roots, or elicitation permissions.
/// Writes are never retried after a transport error, because the server may already have applied them.
public actor MCPClient {
    public let profile: MCPConnectionProfile
    private let secrets: MCPConnectionSecrets
    private let session: URLSession
    private let timeout: TimeInterval
    private var stdio: MCPStdioTransport?
    private var sessionID: String?
    private var protocolVersion: String?
    private var connected = false
    private var busy = false
    private var disconnecting = false
    private var tools: [MCPTool] = []
    private var revision = UUID()
    private let maximumBytes = 4_194_304

    public init(
        profile: MCPConnectionProfile,
        secrets: MCPConnectionSecrets = MCPConnectionSecrets(),
        timeout: TimeInterval = 60
    ) throws {
        try self.init(profile: profile, secrets: secrets, timeout: timeout, configuration: .ephemeral)
    }

    init(
        profile: MCPConnectionProfile,
        secrets: MCPConnectionSecrets = MCPConnectionSecrets(),
        timeout: TimeInterval = 60,
        configuration: URLSessionConfiguration
    ) throws {
        self.profile = try profile.validated()
        self.secrets = try secrets.validated()
        guard timeout.isFinite, (0.1...300).contains(timeout) else {
            throw MCPError.configuration("MCP timeout must be between 0.1 and 300 seconds.")
        }
        self.timeout = timeout
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        // Local MCP credentials must never pass through a configured web proxy.
        if self.profile.transport == .http, let host = URL(string: self.profile.endpoint)?.host,
            ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased()) {
            configuration.connectionProxyDictionary = [:]
        }
        session = URLSession(configuration: configuration, delegate: MCPRejectRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel(); stdio?.close() }

    public func connect() async throws -> [MCPTool] {
        guard !busy, !disconnecting else { throw MCPError.busy }
        if connected { return tools }
        guard profile.enabled else { throw MCPError.configuration("Enable this MCP connection before connecting.") }
        busy = true
        defer { busy = false }
        let currentRevision = revision
        do {
            if profile.transport == .stdio {
                stdio = try MCPStdioTransport(profile: profile, secrets: secrets, timeout: timeout)
            }
            let result = try await request(
                "initialize",
                params: [
                    "protocolVersion": .string("2025-11-25"),
                    "capabilities": .object([:]),
                    "clientInfo": .object(["name": .string("Vyron"), "version": .string("1.0.0")])
                ]
            )
            guard case .string(let version) = result["protocolVersion"],
                ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"].contains(version)
            else {
                throw MCPError.protocolError("The MCP server selected an unsupported protocol version.")
            }
            protocolVersion = version
            try await notify("notifications/initialized")
            guard case .object(let capabilities) = result["capabilities"], capabilities["tools"] != nil else {
                throw MCPError.protocolError("This MCP server does not advertise tools.")
            }
            var discovered: [MCPTool] = []
            var cursor: String?
            var seenCursors = Set<String>()
            repeat {
                try Task.checkCancellation()
                let page = try await request("tools/list", params: cursor.map { ["cursor": .string($0)] } ?? [:])
                guard case .array(let values) = page["tools"] else {
                    throw MCPError.protocolError("The MCP server returned an invalid tool list.")
                }
                for value in values {
                    let tool = try JSONDecoder().decode(MCPTool.self, from: JSONEncoder().encode(value))
                    guard !tool.name.isEmpty, tool.name.count <= 128,
                        tool.name.unicodeScalars.allSatisfy({
                            CharacterSet(
                                charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-"
                            ).contains($0)
                        }),
                        tool.inputSchema["type"] == .string("object"), (tool.description?.utf8.count ?? 0) <= 16_384,
                        try JSONEncoder().encode(tool).count <= 65_536
                    else {
                        throw MCPError.protocolError("The MCP server advertised an invalid tool definition.")
                    }
                    discovered.append(tool)
                }
                guard discovered.count <= 256, Set(discovered.map(\.name)).count == discovered.count,
                    try JSONEncoder().encode(discovered).count <= 1_048_576
                else {
                    throw MCPError.protocolError("The MCP server returned too many tools or duplicate tool names.")
                }
                if let next = page["nextCursor"], next != .null {
                    guard case .string(let nextCursor) = next, !nextCursor.isEmpty, nextCursor.utf8.count <= 4_096,
                        seenCursors.insert(nextCursor).inserted, seenCursors.count <= 32
                    else {
                        throw MCPError.protocolError("The MCP server returned invalid pagination.")
                    }
                    cursor = nextCursor
                } else {
                    cursor = nil
                }
            } while cursor != nil
            guard currentRevision == revision else { throw MCPError.disconnected }
            tools = discovered
            connected = true
            return tools
        } catch {
            stdio?.close(); stdio = nil
            sessionID = nil; protocolVersion = nil; tools = []; connected = false
            throw normalized(error)
        }
    }

    public func callTool(
        name: String,
        arguments: [String: DevelopmentJSONValue],
        approved: Bool = false
    ) async throws -> MCPToolResult {
        guard connected, let tool = tools.first(where: { $0.name == name }) else { throw MCPError.disconnected }
        guard !busy, !disconnecting else { throw MCPError.busy }
        if !tool.isReadOnly {
            guard profile.permission == .askForWrites else {
                throw MCPError.configuration(
                    "This MCP connection allows read-only tools. Change its permission to review write operations."
                )
            }
            guard approved else {
                throw MCPError.configuration(
                    "Review and approve this MCP tool call before allowing it to make changes."
                )
            }
        }
        guard try JSONEncoder().encode(arguments).count <= 262_144 else {
            throw MCPError.configuration("The MCP tool arguments exceed the size limit.")
        }
        busy = true
        defer { busy = false }
        let currentRevision = revision
        do {
            let result = try await request(
                "tools/call",
                params: ["name": .string(name), "arguments": .object(arguments)]
            )
            try Task.checkCancellation()
            guard currentRevision == revision else { throw MCPError.disconnected }
            return try JSONDecoder().decode(MCPToolResult.self, from: JSONEncoder().encode(result))
        } catch { throw normalized(error) }
    }

    public func disconnect() async {
        guard !disconnecting else { return }
        disconnecting = true
        defer { disconnecting = false }
        revision = UUID(); connected = false; tools = []
        stdio?.close(); stdio = nil
        let activeTasks = await session.allTasks
        activeTasks.forEach { $0.cancel() }
        if let sessionID, profile.transport == .http, var deletion = try? httpRequest(body: nil) {
            deletion.httpMethod = "DELETE"
            deletion.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
            deletion.timeoutInterval = min(timeout, 3)
            _ = try? await session.data(for: deletion)
        }
        sessionID = nil; protocolVersion = nil
    }

    private func request(_ method: String, params: MCPObject) async throws -> MCPObject {
        let id = UUID().uuidString
        let message: MCPObject = [
            "jsonrpc": .string("2.0"), "id": .string(id), "method": .string(method), "params": .object(params)
        ]
        let data = try JSONEncoder().encode(message)
        let reply: MCPObject
        switch profile.transport {
        case .http: reply = try await exchangeHTTP(data, expectedID: id)
        case .stdio:
            guard let stdio else { throw MCPError.disconnected }
            reply = try await stdio.request(data, id: id)
        }
        guard reply["jsonrpc"] == .string("2.0"), reply["id"] == .string(id) else {
            throw MCPError.protocolError("The MCP server returned a mismatched response.")
        }
        if case .object(let error) = reply["error"], case .number(let code) = error["code"], code.isFinite,
            abs(code) <= Double(Int32.max) {
            throw MCPError.server(Int(code))
        }
        guard case .object(let result) = reply["result"] else {
            throw MCPError.protocolError("The MCP server returned an invalid result.")
        }
        return result
    }

    private func notify(_ method: String) async throws {
        let data = try JSONEncoder().encode(["jsonrpc": DevelopmentJSONValue.string("2.0"), "method": .string(method)]
        )
        switch profile.transport {
        case .http: _ = try await exchangeHTTP(data, expectedID: nil)
        case .stdio:
            guard let stdio else { throw MCPError.disconnected }
            try stdio.notify(data)
        }
    }

    private func httpRequest(body: Data?) throws -> URLRequest {
        var components = URLComponents(
            url: try MCPEndpoint.validated(profile.endpoint),
            resolvingAgainstBaseURL: false
        )!
        if !secrets.queryParameters.isEmpty {
            components.queryItems = secrets.queryParameters.sorted(by: { $0.key < $1.key }).map {
                URLQueryItem(name: $0.key, value: $0.value)
            }
        }
        guard let url = components.url else { throw MCPError.configuration("The MCP URL could not be constructed.") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.httpBody = body; request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if !secrets.bearerToken.isEmpty {
            request.setValue("Bearer " + secrets.bearerToken, forHTTPHeaderField: "Authorization")
        }
        for (name, value) in secrets.headers { request.setValue(value, forHTTPHeaderField: name) }
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        if let protocolVersion { request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version") }
        return request
    }

    private func exchangeHTTP(_ data: Data, expectedID: String?) async throws -> MCPObject {
        let (bytes, response) = try await session.bytes(for: httpRequest(body: data))
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else {
            throw MCPError.protocolError("The MCP server returned an invalid HTTP response.")
        }
        guard (200..<300).contains(response.statusCode) else { throw MCPError.http(response.statusCode) }
        if let id = response.value(forHTTPHeaderField: "Mcp-Session-Id") {
            guard !id.isEmpty, id.utf8.count <= 4_096, id.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else {
                throw MCPError.protocolError("The MCP server returned an invalid session identifier.")
            }
            sessionID = id
        }
        guard let expectedID else { return [:] }
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("text/event-stream") {
            var line = Data(); var eventData: [String] = []; var total = 0
            for try await byte in bytes {
                try Task.checkCancellation()
                total += 1
                guard total <= maximumBytes else {
                    throw MCPError.protocolError("The MCP response exceeds the size limit.")
                }
                if byte == 10 {
                    let text = String(decoding: line, as: UTF8.self).trimmingCharacters(
                        in: CharacterSet(charactersIn: "\r")
                    )
                    line.removeAll(keepingCapacity: true)
                    if text.isEmpty {
                        if let result = try await consumeEvent(eventData, expectedID: expectedID) { return result }
                        eventData.removeAll(keepingCapacity: true)
                    } else if text.hasPrefix("data:") {
                        let value = text.dropFirst(5)
                        eventData.append(String(value.hasPrefix(" ") ? value.dropFirst() : value))
                    }
                } else {
                    line.append(byte)
                }
            }
            if let result = try await consumeEvent(eventData, expectedID: expectedID) { return result }
            throw MCPError.protocolError("The MCP stream ended before the result arrived.")
        }
        guard contentType.contains("application/json") else {
            throw MCPError.protocolError("The MCP server returned an unsupported content type.")
        }
        var body = Data()
        for try await byte in bytes {
            guard body.count < maximumBytes else {
                throw MCPError.protocolError("The MCP response exceeds the size limit.")
            }
            body.append(byte)
        }
        let reply = try JSONDecoder().decode(MCPObject.self, from: body)
        guard reply["id"] == .string(expectedID) else {
            throw MCPError.protocolError("The MCP server returned a mismatched response.")
        }
        return reply
    }

    private func consumeEvent(_ lines: [String], expectedID: String) async throws -> MCPObject? {
        let text = lines.joined(separator: "\n")
        guard !text.isEmpty else { return nil }
        let message = try JSONDecoder().decode(MCPObject.self, from: Data(text.utf8))
        if message["id"] == .string(expectedID), message["method"] == nil { return message }
        if message["id"] != nil, case .string(let method) = message["method"] {
            // Do not grant filesystem roots, model sampling, or elicitation to a server.
            var response: MCPObject = ["jsonrpc": .string("2.0"), "id": message["id"]!]
            response[method == "ping" ? "result" : "error"] =
                method == "ping"
                ? .object([:])
                : .object(["code": .number(-32601), "message": .string("Client capability not supported")])
            _ = try await exchangeHTTP(JSONEncoder().encode(response), expectedID: nil)
        }
        return nil
    }

    private func normalized(_ error: any Error) -> any Error {
        if error is CancellationError || Task.isCancelled { return CancellationError() }
        if let url = error as? URLError, url.code == .cancelled { return CancellationError() }
        if let error = error as? MCPError { return error }
        if let url = error as? URLError, url.code == .timedOut { return MCPError.timeout }
        // Foundation error descriptions can include the URL and Penpot userToken.
        return MCPError.transport(
            "Could not communicate with the MCP server. Check that it is running and that its credentials are correct."
        )
    }
}
