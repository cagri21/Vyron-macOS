import Foundation
import zlib

enum VyronWebsiteSitemapCompression {
    private static let gzipSignature: [UInt8] = [0x1f, 0x8b]
    private static let gzipWindowBits = MAX_WBITS + 16

    static func decodeIfNeeded(_ data: Data, maximumBytes: Int) -> Data? {
        guard data.count <= maximumBytes else { return nil }
        guard data.starts(with: gzipSignature) else { return data }
        var stream = z_stream()
        guard inflateInit2_(&stream, gzipWindowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }

        var output = Data(count: maximumBytes + 1)
        let result = data.withUnsafeBytes { input in
            output.withUnsafeMutableBytes { destination in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(destination.count)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard result == Z_STREAM_END, stream.avail_in == 0, stream.total_out <= maximumBytes else { return nil }
        output.count = Int(stream.total_out)
        return output
    }
}
