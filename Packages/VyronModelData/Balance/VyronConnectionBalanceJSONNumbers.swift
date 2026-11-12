import Foundation
import VyronModelDomain

/// Validate numeric lexemes before decoding; amounts must never silently round through Double or Decimal overflow.
enum VyronConnectionBalanceJSONNumbers {
    static func validate(_ data: Data) throws {
        let bytes = [UInt8](data)
        var index = 0
        var inString = false
        var escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 92 {
                    escaped = true
                } else if byte == 34 {
                    inString = false
                }
                index += 1
            } else if byte == 34 {
                inString = true
                index += 1
            } else if byte == 45 || (48...57).contains(byte) {
                let start = index
                while index < bytes.count, isNumberByte(bytes[index]) { index += 1 }
                guard let literal = String(bytes: bytes[start..<index], encoding: .utf8) else {
                    throw VyronConnectionBalanceError.invalidResponse
                }
                _ = try VyronConnectionBalanceDecimal.parse(literal)
            } else {
                index += 1
            }
        }
    }

    private static func isNumberByte(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || [43, 45, 46, 69, 101].contains(byte)
    }
}
