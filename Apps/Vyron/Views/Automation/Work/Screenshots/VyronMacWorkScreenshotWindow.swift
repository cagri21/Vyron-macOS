import Foundation

struct VyronMacWorkScreenshotWindow: Encodable, Sendable {
    let sourceID: String
    let name: String
    let applicationID: String
    let processID: Int32

    private enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case name
        case applicationID = "application_id"
        case processID = "process_id"
    }
}
