import Foundation

enum VyronConversationCompactionText {
    static func prefix(_ text: String, bytes: Int) -> String {
        var data = text.utf8.prefix(max(0, bytes))
        while String(bytes: data, encoding: .utf8) == nil { data = data.dropLast() }
        return String(decoding: data, as: UTF8.self)
    }

    static func excerpt(_ text: String, bytes: Int) -> String {
        guard text.utf8.count > bytes else { return text }
        let marker = "\n[... omitted ...]\n"
        guard bytes > marker.utf8.count else { return prefix(marker, bytes: bytes) }
        let available = bytes - marker.utf8.count
        let beginning = prefix(text, bytes: (available + 1) / 2)
        var ending = text.utf8.suffix(available / 2)
        while String(bytes: ending, encoding: .utf8) == nil { ending = ending.dropFirst() }
        return beginning + marker + String(decoding: ending, as: UTF8.self)
    }
}
