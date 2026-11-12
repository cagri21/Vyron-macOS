import Foundation

enum VyronChromeBridgePolicy {
    static let messageLimit = 512 * 1_024
    static let heartbeatLifetime: TimeInterval = 15
    static let methods: Set<String> = ["tabs", "snapshot", "click", "fill", "navigate", "back", "forward", "reload"]
    static let maximumPending = 32

    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/VyronAI/ChromeBridge/Sessions", isDirectory: true
        )
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(value)
        guard data.count <= messageLimit else { throw VyronChromeBridgeError.invalidMessage }
        return data
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= messageLimit else { throw VyronChromeBridgeError.invalidMessage }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }
}
