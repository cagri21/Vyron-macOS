import Foundation

struct VyronResponsesTestResponse: Sendable {
    let body: Data
    let statusCode: Int
    let fragmentBytes: Int
    let holdOpen: Bool

    init(body: String, statusCode: Int = 200, fragmentBytes: Int = 7, holdOpen: Bool = false) {
        self.body = Data(body.utf8)
        self.statusCode = statusCode
        self.fragmentBytes = max(1, fragmentBytes)
        self.holdOpen = holdOpen
    }
}
