import Combine
import Foundation
import VyronCore

struct MCPActionReview: Identifiable, Sendable {
    let id = UUID()
    let connectionName: String
    let toolName: String
    let arguments: String
}

struct MCPToolSession: Sendable {
    struct Binding: Sendable {
        let profile: MCPConnectionProfile
        let tool: MCPTool
        let client: MCPClient
        let revision: UUID
    }
    let tools: [DevelopmentExternalTool]
    let bindings: [String: Binding]
}

@MainActor
final class MCPConnectionsModel: ObservableObject {
    @Published private(set) var profiles: [MCPConnectionProfile] = []
    @Published private(set) var tools: [UUID: [MCPTool]] = [:]
    @Published private(set) var statuses: [UUID: String] = [:]
    @Published private(set) var busy = Set<UUID>()
    @Published var error: String?
    @Published private(set) var pendingReview: MCPActionReview?
    private var clients: [UUID: MCPClient] = [:]
    private var revisions: [UUID: UUID] = [:]
    private var connectionTasks: [UUID: Task<Void, Never>] = [:]
    private var reviewContinuation: CheckedContinuation<Bool, Never>?
    private var writable = true
    private let store: MCPConnectionStore
    private let credentials: MCPCredentialStore
    private let clientFactory: @Sendable (MCPConnectionProfile, MCPConnectionSecrets) throws -> MCPClient

    init(
        store: MCPConnectionStore,
        credentials: MCPCredentialStore = MCPCredentialStore(),
        clientFactory: @escaping @Sendable (MCPConnectionProfile, MCPConnectionSecrets) throws -> MCPClient = {
            try MCPClient(profile: $0, secrets: $1)
        }
    ) {
        self.credentials = credentials
        self.clientFactory = clientFactory
        self.store = store
        do { profiles = try store.load() } catch {
            writable = false
            self.error = VyronControlText.mcpUnreadable
        }
    }

    var connectedCount: Int { clients.count }
    func isConnected(_ id: UUID) -> Bool { clients[id] != nil }
    func secrets(for id: UUID) throws -> MCPConnectionSecrets { try credentials.load(for: id) }

    /// Reload saved profiles without connecting services or reading credentials.
    func refreshProfiles() {
        guard busy.isEmpty else { return }
        do {
            let updated = try store.load()
            for profile in profiles where !updated.contains(profile) {
                disconnect(profile.id)
            }
            profiles = updated
            writable = true
            error = nil
        } catch {
            writable = false
            self.error = VyronControlText.mcpUnreadable
        }
    }

    @discardableResult
    func save(_ profile: MCPConnectionProfile, secrets: MCPConnectionSecrets) -> Bool {
        guard writable else {
            error = VyronControlText.mcpResolveFile; return false
        }
        guard !busy.contains(profile.id) else { return false }
        do {
            let profile = try profile.validated()
            var updated = profiles.filter { $0.id != profile.id }
            updated.append(profile)
            let priorSecrets = try credentials.load(for: profile.id)
            try credentials.save(secrets, for: profile.id)
            do { try store.save(updated) } catch { try? credentials.save(priorSecrets, for: profile.id); throw error }
            disconnect(profile.id)
            profiles = updated
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func remove(_ id: UUID) {
        guard writable else { return }
        do {
            let updated = profiles.filter { $0.id != id }
            try store.save(updated)
            disconnect(id)
            profiles = updated
            try credentials.remove(for: id)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func setEnabled(_ enabled: Bool, for profile: MCPConnectionProfile) {
        var updated = profile
        updated.enabled = enabled
        do { _ = save(updated, secrets: try credentials.load(for: profile.id)) } catch {
            self.error = error.localizedDescription
        }
    }

    func connect(_ profile: MCPConnectionProfile) {
        guard profile.enabled, !busy.contains(profile.id) else { return }
        disconnect(profile.id)
        let revision = UUID()
        revisions[profile.id] = revision
        busy.insert(profile.id)
        statuses[profile.id] = VyronControlText.connecting
        error = nil
        connectionTasks[profile.id] = Task { [weak self] in
            guard let self else { return }
            var pendingClient: MCPClient?
            do {
                let client = try clientFactory(profile, credentials.load(for: profile.id))
                pendingClient = client
                let catalog = try await client.connect()
                guard revisions[profile.id] == revision, !Task.isCancelled else { await client.disconnect(); return }
                clients[profile.id] = client
                tools[profile.id] = catalog
                statuses[profile.id] = VyronControlText.connectedTools(catalog.count)
            } catch {
                await pendingClient?.disconnect()
                guard revisions[profile.id] == revision else { return }
                statuses[profile.id] =
                    Task.isCancelled ? VyronControlText.disconnected : VyronControlText.connectionFailed
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
            guard revisions[profile.id] == revision else { return }
            busy.remove(profile.id)
            connectionTasks[profile.id] = nil
        }
    }

    func disconnect(_ id: UUID) {
        revisions[id] = UUID()
        connectionTasks.removeValue(forKey: id)?.cancel()
        if let client = clients.removeValue(forKey: id) { Task { await client.disconnect() } }
        tools[id] = nil
        busy.remove(id)
        statuses[id] = VyronControlText.disconnected
        if pendingReview?.connectionName == profiles.first(where: { $0.id == id })?.name { respondToReview(false) }
    }

    func snapshot(mode: ComposerMode) throws -> MCPToolSession {
        var definitions: [DevelopmentExternalTool] = []
        var bindings: [String: MCPToolSession.Binding] = [:]
        for profile in profiles where profile.enabled {
            guard let client = clients[profile.id], let revision = revisions[profile.id] else { continue }
            for (index, tool) in (tools[profile.id] ?? []).enumerated() {
                guard tool.isReadOnly || (profile.permission == .askForWrites && mode == .agent) else { continue }
                let name = "mcp_\(profile.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(12))_\(index)"
                definitions.append(
                    .init(
                        name: name,
                        description:
                            "\(profile.name) / \(tool.name): \(String((tool.description ?? "").prefix(1_200)))",
                        inputSchema: tool.inputSchema,
                        isReadOnly: tool.isReadOnly
                    )
                )
                bindings[name] = .init(profile: profile, tool: tool, client: client, revision: revision)
            }
        }
        guard definitions.count <= 64 else {
            throw DevelopmentAgentError.invalidTool(
                VyronControlText.mcpToolLimit
            )
        }
        return MCPToolSession(tools: definitions, bindings: bindings)
    }

    func execute(_ call: DevelopmentToolCall, session: MCPToolSession) async throws -> DevelopmentExternalResult {
        guard let binding = session.bindings[call.function.name],
            revisions[binding.profile.id] == binding.revision,
            profiles.contains(binding.profile), clients[binding.profile.id] != nil
        else {
            throw DevelopmentAgentError.invalidTool(VyronControlText.mcpChanged)
        }
        if !binding.tool.isReadOnly {
            guard binding.profile.permission == .askForWrites else {
                throw DevelopmentAgentError.invalidTool(VyronControlText.mcpReadOnly)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let arguments = String(decoding: try encoder.encode(call.function.arguments), as: UTF8.self)
            let request = MCPActionReview(
                connectionName: binding.profile.name,
                toolName: binding.tool.name,
                arguments: arguments
            )
            let approved = await review(request)
            try Task.checkCancellation()
            guard approved else {
                return .init(
                    text:
                        "The user declined this integration action. No tool was called. Do not bypass this decision using another tool or implementation.",
                    isError: true
                )
            }
        }
        try Task.checkCancellation()
        guard revisions[binding.profile.id] == binding.revision else {
            throw DevelopmentAgentError.invalidTool(VyronControlText.mcpDisconnected)
        }
        let result = try await binding.client.callTool(
            name: binding.tool.name,
            arguments: call.function.arguments,
            approved: !binding.tool.isReadOnly
        )
        return .init(text: result.readableText, isError: result.isError)
    }

    // Local Office tools share the same native review and cancellation owner.
    func review(_ request: MCPActionReview) async -> Bool {
        await withTaskCancellationHandler {
            guard !Task.isCancelled else { return false }
            return await withCheckedContinuation { continuation in
                respondToReview(false)
                pendingReview = request
                reviewContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if self?.pendingReview?.id == request.id { self?.respondToReview(false) }
            }
        }
    }

    func respondToReview(_ approved: Bool) {
        let continuation = reviewContinuation
        reviewContinuation = nil
        pendingReview = nil
        continuation?.resume(returning: approved)
    }

    func shutdown() {
        respondToReview(false)
        for id in Set(clients.keys).union(connectionTasks.keys) { disconnect(id) }
    }

    /// Read only the named Penpot URL. Never display or persist its URL credentials.
    func importExistingPenpot() {
        do {
            let configURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                ".codex/config.toml"
            )
            let config = try String(contentsOf: configURL, encoding: .utf8)
            var inPenpot = false
            var url: String?
            for line in config.components(separatedBy: .newlines) {
                let line = line.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("[") { inPenpot = line == "[mcp_servers.penpot]"; continue }
                guard inPenpot, line.hasPrefix("url"), let equal = line.firstIndex(of: "=") else { continue }
                let value = line[line.index(after: equal)...].trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\""), let end = value.dropFirst().firstIndex(of: "\"") {
                    url = String(value[value.index(after: value.startIndex)..<end])
                }
            }
            guard let url else {
                error = VyronControlText.penpotNotFound;
                return
            }
            let separated = try MCPEndpoint.separateSecrets(url)
            let existing = profiles.first { $0.name.lowercased() == "penpot" }
            let profile = MCPConnectionProfile(
                id: existing?.id ?? UUID(),
                name: "Penpot",
                endpoint: separated.endpoint,
                permission: .askForWrites
            )
            if save(profile, secrets: .init(queryParameters: separated.queryParameters)) { connect(profile) }
        } catch {
            self.error = VyronControlText.penpotImportFailed
        }
    }
}
