import Foundation

/// Explicit reads are never evicted: reaching the bound leaves the previous state intact.
struct VyronNotificationReadState: Codable, Equatable, Sendable {
    static let empty = Self()
    private(set) var readIDs: Set<VyronNotificationID>

    init() { readIDs = [] }

    func isRead(_ id: VyronNotificationID) -> Bool { readIDs.contains(id) }

    mutating func markRead(_ id: VyronNotificationID) throws {
        try markAllRead(ids: [id])
    }

    mutating func markAllRead(ids: [VyronNotificationID]) throws {
        let updated = readIDs.union(ids)
        guard updated.count <= VyronNotificationLimits.maximumReadMarkers else {
            throw VyronNotificationReadError.capacityExceeded
        }
        readIDs = updated
    }

    func validate() throws {
        guard readIDs.count <= VyronNotificationLimits.maximumReadMarkers else {
            throw VyronNotificationReadError.capacityExceeded
        }
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .version) == 1 else {
            throw VyronNotificationReadError.invalidStore
        }
        let records = try values.decode([VyronNotificationID].self, forKey: .readIDs)
        guard records.count <= VyronNotificationLimits.maximumReadMarkers,
            Set(records).count == records.count else { throw VyronNotificationReadError.invalidStore }
        readIDs = Set(records)
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(1, forKey: .version)
        try values.encode(readIDs.sorted { $0.sortKey < $1.sortKey }, forKey: .readIDs)
    }
}
