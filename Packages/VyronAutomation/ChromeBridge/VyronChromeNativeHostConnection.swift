import Foundation

/// One foreground native-messaging connection owns one isolated mailbox and never replays requests.
final class VyronChromeNativeHostConnection {
    private let mailbox: VyronChromeBridgeMailbox
    private let id: UUID
    private let extensionID: String
    private var greeted = false
    private var pending: [UUID: Double] = [:]
    private var dispatched: [UUID: Double] = [:]

    init(root: VyronChromeBridgeDirectory, id: UUID, extensionID: String) throws {
        self.id = id
        self.extensionID = extensionID
        mailbox = try VyronChromeBridgeMailbox(root: root, id: id, create: true)
    }

    func accept(_ data: Data) throws {
        let signal = try VyronChromeBridgePolicy.decode(VyronChromeBridgeSignal.self, from: data)
        guard signal.version == 1 else { throw VyronChromeBridgeError.invalidMessage }
        if let type = signal.type {
            guard signal.id == nil,
                (type == "hello" && !greeted) || (type == "heartbeat" && greeted)
            else { throw VyronChromeBridgeError.invalidMessage }
            greeted = true
            try heartbeat()
            return
        }
        guard greeted else { throw VyronChromeBridgeError.invalidMessage }
        let response = try VyronChromeBridgePolicy.decode(VyronChromeBridgeResponse.self, from: data)
        try response.validate()
        // Late, duplicated, cancelled and unsolicited responses cannot create mailbox entries.
        guard let expiry = pending.removeValue(forKey: response.id),
            expiry > Date().timeIntervalSince1970 * 1_000
        else { return }
        let name = response.id.uuidString + ".json"
        if try mailbox.cancellations.read(name) != nil {
            try mailbox.cancellations.remove(name)
            return
        }
        try mailbox.responses.write(name, data: data)
        try heartbeat()
    }

    func outgoing() throws -> [Data] {
        guard greeted else { return [] }
        var messages: [Data] = []
        let now = Date().timeIntervalSince1970 * 1_000
        dispatched = dispatched.filter { $0.value > now }
        // Cancellation precedes dispatch, and also dismisses extension review after dispatch.
        for name in try mailbox.cancellations.names() {
            guard let requestID = Self.requestID(name) else { throw VyronChromeBridgeError.invalidPath }
            try mailbox.requests.remove(name)
            try mailbox.responses.remove(name)
            if pending.removeValue(forKey: requestID) != nil {
                messages.append(try cancellation(requestID))
            }
            try mailbox.cancellations.remove(name)
        }
        for (requestID, expiry) in pending where expiry <= now {
            pending.removeValue(forKey: requestID)
            messages.append(try cancellation(requestID))
        }
        for name in try mailbox.requests.names().sorted() {
            guard let requestID = Self.requestID(name) else { throw VyronChromeBridgeError.invalidPath }
            guard pending.count < VyronChromeBridgePolicy.maximumPending else { break }
            guard let data = try mailbox.requests.read(name) else { continue }
            let request = try VyronChromeBridgePolicy.decode(VyronChromeBridgeRequest.self, from: data)
            guard request.id == requestID else { throw VyronChromeBridgeError.invalidMessage }
            if request.expiresAt <= now {
                try mailbox.requests.remove(name)
                continue
            }
            try request.validate()
            guard dispatched[requestID] == nil else { throw VyronChromeBridgeError.invalidMessage }
            // Claim by deletion before stdout: a crash may lose a request but cannot replay a mutation.
            try mailbox.requests.remove(name)
            if try mailbox.cancellations.read(name) != nil { continue }
            pending[requestID] = request.expiresAt
            dispatched[requestID] = request.expiresAt
            messages.append(data)
        }
        return messages
    }

    private func heartbeat() throws {
        try mailbox.update(VyronChromeBridgeSession(
            id: id, extensionID: extensionID, updatedAt: Date(), hostSupportsOpeningTabs: true
        ))
    }

    private func cancellation(_ requestID: UUID) throws -> Data {
        try VyronChromeBridgePolicy.encode(VyronChromeBridgeSignal(version: 1, type: "cancel", id: requestID))
    }

    private static func requestID(_ name: String) -> UUID? {
        guard name.hasSuffix(".json"), let id = UUID(uuidString: String(name.dropLast(5))),
            name == id.uuidString + ".json"
        else { return nil }
        return id
    }
}
