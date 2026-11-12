import Foundation

enum VyronDevelopmentTaskText {
    static func prefix(_ text: String, maximumBytes: Int) -> String {
        guard maximumBytes > 0 else { return "" }
        let bytes = Data(text.utf8.prefix(maximumBytes))
        for removed in 0...min(3, bytes.count) {
            if let value = String(data: bytes.dropLast(removed), encoding: .utf8) { return value }
        }
        return ""
    }

    static func isValid(_ text: String, maximumBytes: Int, permitsEmpty: Bool = false) -> Bool {
        (permitsEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && text.utf8.count <= maximumBytes
            && !text.unicodeScalars.contains(where: { $0.value == 0 })
    }
}
