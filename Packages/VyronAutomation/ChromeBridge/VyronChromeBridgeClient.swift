import Foundation

public actor VyronChromeBridgeClient {
    private let root: URL
    private var inFlight: Set<UUID> = []
    private var attempted: [UUID: Double] = [:]

    public init(root: URL? = nil) { self.root = root ?? VyronChromeBridgePolicy.root }

    public func sessions() throws -> [VyronChromeBridgeSession] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let directory = try VyronChromeBridgeDirectory.open(root, create: false)
        var sessions: [VyronChromeBridgeSession] = []
        for name in try directory.names() {
            guard let id = UUID(uuidString: name), name == id.uuidString else { continue }
            let entry = try directory.child(name, create: false)
            guard let data = try entry.read("session.json") else { continue }
            let session = try VyronChromeBridgePolicy.decode(VyronChromeBridgeSession.self, from: data)
            if session.id == id, session.isLive() { sessions.append(session) }
        }
        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Sends once. A cancelled or expired mutation is never replayed on another connection.
    public func send(
        _ request: VyronChromeBridgeRequest,
        to sessionID: UUID
    ) async throws -> VyronChromeBridgeResponse {
        try Task.checkCancellation()
        try request.validate()
        attempted = attempted.filter { $0.value > Date().timeIntervalSince1970 * 1_000 }
        guard inFlight.count < VyronChromeBridgePolicy.maximumPending,
            attempted[request.id] == nil, let session = try sessions().first(where: { $0.id == sessionID })
        else { throw VyronChromeBridgeError.unavailable }
        if request.method == VyronChromeBridgePolicy.openTabsMethod, session.hostSupportsOpeningTabs != true {
            throw VyronChromeBridgeError.hostUpdateRequired
        }
        let directory = try VyronChromeBridgeDirectory.open(root, create: false)
        let mailbox = try VyronChromeBridgeMailbox(root: directory, id: sessionID, create: false)
        let name = request.id.uuidString + ".json"
        inFlight.insert(request.id)
        attempted[request.id] = request.expiresAt
        defer { inFlight.remove(request.id) }
        try mailbox.requests.write(name, data: VyronChromeBridgePolicy.encode(request))
        do {
            while true {
                try Task.checkCancellation()
                if let data = try mailbox.responses.read(name) {
                    let response = try VyronChromeBridgePolicy.decode(VyronChromeBridgeResponse.self, from: data)
                    try response.validate()
                    guard response.id == request.id else { throw VyronChromeBridgeError.invalidMessage }
                    try Task.checkCancellation()
                    try mailbox.responses.remove(name)
                    try mailbox.requests.remove(name)
                    return response
                }
                guard Date().timeIntervalSince1970 * 1_000 < request.expiresAt else {
                    throw VyronChromeBridgeError.timeout
                }
                guard let session = try mailbox.metadata(), session.id == sessionID, session.isLive() else {
                    throw VyronChromeBridgeError.unavailable
                }
                try await Task.sleep(for: .milliseconds(100))
            }
        } catch {
            do { try mailbox.cancel(request.id) }
            catch {
                // Keep cancellation distinct while making cleanup failure observable without exposing page data.
                FileHandle.standardError.write(Data("Vyron Chrome bridge: request cancellation cleanup failed.\n".utf8))
            }
            throw error
        }
    }
}
