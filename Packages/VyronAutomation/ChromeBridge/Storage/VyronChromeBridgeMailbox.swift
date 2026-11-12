import Foundation

struct VyronChromeBridgeMailbox {
    let session: VyronChromeBridgeDirectory
    let requests: VyronChromeBridgeDirectory
    let responses: VyronChromeBridgeDirectory
    let cancellations: VyronChromeBridgeDirectory

    init(root: VyronChromeBridgeDirectory, id: UUID, create: Bool) throws {
        session = try root.child(id.uuidString, create: create)
        requests = try session.child("requests", create: create)
        responses = try session.child("responses", create: create)
        cancellations = try session.child("cancellations", create: create)
    }

    func metadata() throws -> VyronChromeBridgeSession? {
        guard let data = try session.read("session.json") else { return nil }
        return try VyronChromeBridgePolicy.decode(VyronChromeBridgeSession.self, from: data)
    }

    func update(_ value: VyronChromeBridgeSession) throws {
        try session.write("session.json", data: VyronChromeBridgePolicy.encode(value), replacing: true)
    }

    func cancel(_ id: UUID) throws {
        let name = id.uuidString + ".json"
        try cancellations.write(name, data: Data("{}".utf8), replacing: true)
        try requests.remove(name)
        try responses.remove(name)
    }

    static func remove(root: VyronChromeBridgeDirectory, id: UUID) throws {
        let mailbox = try Self(root: root, id: id, create: false)
        // Withdraw discovery before cleanup so a closing host cannot be selected by a new request.
        try mailbox.session.remove("session.json")
        for directory in [mailbox.requests, mailbox.responses, mailbox.cancellations] {
            for name in try directory.names() { try directory.remove(name) }
        }
        for name in ["requests", "responses", "cancellations"] { try mailbox.session.remove(name, directory: true) }
        try root.remove(id.uuidString, directory: true)
    }
}
