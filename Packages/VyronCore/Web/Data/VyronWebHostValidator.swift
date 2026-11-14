import Darwin
import Foundation

/// DNS runs on a utility queue so the system resolver never blocks a cooperative task executor.
enum VyronWebHostValidator {
    static func validate(_ host: String) async throws {
        try Task.checkCancellation()
        let addresses: [String] = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do { continuation.resume(returning: try resolvedAddresses(host)) }
                catch { continuation.resume(throwing: error) }
            }
        }
        try Task.checkCancellation()
        guard !addresses.isEmpty, addresses.allSatisfy(isPublicAddress) else { throw VyronWebError.unsafeURL }
    }

    static func isPublicAddress(_ value: String) -> Bool {
        var ipv4 = in_addr()
        if inet_pton(AF_INET, value, &ipv4) == 1 {
            let address = UInt32(bigEndian: ipv4.s_addr)
            let first = address >> 24
            let second = (address >> 16) & 255
            let third = (address >> 8) & 255
            guard first != 0, first != 10, first != 127, first < 224,
                !(first == 100 && (64...127).contains(second)),
                !(first == 169 && second == 254),
                !(first == 172 && (16...31).contains(second)),
                !(first == 192 && second == 168),
                !(first == 192 && second == 0 && (third == 0 || third == 2)),
                !(first == 192 && second == 88 && third == 99),
                !(first == 198 && (second == 18 || second == 19)),
                !(first == 198 && second == 51 && third == 100),
                !(first == 203 && second == 0 && third == 113)
            else { return false }
            return true
        }
        var ipv6 = in6_addr()
        guard inet_pton(AF_INET6, value, &ipv6) == 1 else { return false }
        let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
        // Public native unicast only; excludes local, mapped, multicast and translation addresses.
        guard bytes[0] & 0xe0 == 0x20,
            !(bytes[0] == 0x20 && bytes[1] == 0x02),
            !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0 && bytes[3] == 0),
            !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8),
            !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0 && bytes[3] == 2),
            !(bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0 && bytes[3] & 0xf0 == 0x10),
            !(bytes[0] == 0x3f && bytes[1] == 0xff && bytes[2] & 0xf0 == 0)
        else { return false }
        return true
    }

    private static func resolvedAddresses(_ host: String) throws -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var head: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &head) == 0, let head else { throw VyronWebError.unavailable }
        defer { freeaddrinfo(head) }
        var addresses: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = head
        while let entry = cursor {
            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(entry.pointee.ai_addr, entry.pointee.ai_addrlen,
                              &name, socklen_t(name.count), nil, 0, NI_NUMERICHOST) == 0 else {
                throw VyronWebError.unavailable
            }
            let addressBytes = name.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
            addresses.append(String(decoding: addressBytes, as: UTF8.self))
            cursor = entry.pointee.ai_next
        }
        return addresses
    }
}
