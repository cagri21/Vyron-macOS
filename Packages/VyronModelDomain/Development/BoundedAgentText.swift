import Foundation

package func boundedAgentPrefix(_ value: String, bytes limit: Int) -> String {
    let data = Data(value.utf8.prefix(max(0, limit)))
    for trim in 0...min(3, data.count) {
        if let text = String(data: data.dropLast(trim), encoding: .utf8) { return text }
    }
    return ""
}

package func boundedAgentSuffix(_ value: String, bytes limit: Int) -> String {
    let data = Data(value.utf8.suffix(max(0, limit)))
    for trim in 0...min(3, data.count) {
        if let text = String(data: data.dropFirst(trim), encoding: .utf8) { return text }
    }
    return ""
}
