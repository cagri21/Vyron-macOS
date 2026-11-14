enum VyronModelHTTP {
    static let authorizationHeader = "Authorization"
    static let acceptHeader = "Accept"
    static let contentTypeHeader = "Content-Type"
    static let cookieHeader = "Cookie"
    static let json = "application/json"
    static let eventStream = "text/event-stream"
    static let binary = "application/octet-stream"
    static let get = "GET"
    static let head = "HEAD"
    static let post = "POST"
    static let delete = "DELETE"

    static func bearer(_ key: String) -> String {
        "Bearer " + key
    }
}
