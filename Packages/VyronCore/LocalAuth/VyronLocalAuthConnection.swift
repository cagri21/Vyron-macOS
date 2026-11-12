import Foundation

struct VyronLocalAuthConnection: Sendable {
    let configuration: VyronLocalAuthConfiguration
    let token: Data
    let generation: UUID

    func request(path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: configuration.endpoint.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = VyronLocalAuthLimits.timeout
        request.setValue("Bearer " + VyronLocalAuthToken.encode(token), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
}
