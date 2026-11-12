import Foundation

struct VyronConnectionBalanceTestReply: Sendable {
    let body: Data
    let statusCode: Int
    let headers: [String: String]
    let holdOpen: Bool

    init(body: String, statusCode: Int = 200, headers: [String: String] = [:], holdOpen: Bool = false) {
        self.body = Data(body.utf8)
        self.statusCode = statusCode
        self.headers = headers
        self.holdOpen = holdOpen
    }
}
