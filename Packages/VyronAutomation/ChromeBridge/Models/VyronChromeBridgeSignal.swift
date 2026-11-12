import Foundation

struct VyronChromeBridgeSignal: Codable {
    let version: Int
    let type: String?
    let id: UUID?
}
