import Foundation

struct VyronChromeNativeFraming {
    private var buffer = Data()

    mutating func append(_ data: Data) throws -> [Data] {
        guard buffer.count + data.count <= VyronChromeBridgePolicy.messageLimit + 65_540 else {
            throw VyronChromeBridgeError.invalidMessage
        }
        buffer.append(data)
        var messages: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).enumerated().reduce(UInt32(0)) { partial, item in
                partial | UInt32(item.element) << (item.offset * 8)
            }
            guard length > 0, length <= VyronChromeBridgePolicy.messageLimit else {
                throw VyronChromeBridgeError.invalidMessage
            }
            let frameSize = Int(length) + 4
            guard buffer.count >= frameSize else { break }
            messages.append(Data(buffer[4..<frameSize]))
            buffer.removeSubrange(0..<frameSize)
        }
        return messages
    }

    func finish() throws {
        guard buffer.isEmpty else { throw VyronChromeBridgeError.invalidMessage }
    }

    static func frame(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= VyronChromeBridgePolicy.messageLimit else {
            throw VyronChromeBridgeError.invalidMessage
        }
        var count = UInt32(data.count).littleEndian
        var frame = withUnsafeBytes(of: &count) { Data($0) }
        frame.append(data)
        return frame
    }
}
