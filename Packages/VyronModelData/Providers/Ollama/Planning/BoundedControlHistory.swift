import Foundation
import VyronModelDomain

/// Keep the newest action results within the request budget without splitting UTF-8 characters.
func boundedControlHistory(_ history: String) -> String {
    let bytes = Data(history.utf8.suffix(4_096))
    for offset in 0...min(3, bytes.count) {
        if let value = String(data: bytes.dropFirst(offset), encoding: .utf8) { return value }
    }
    return ""
}
