import Foundation

actor VyronResponsesTestState {
    typealias Handler = @Sendable (URLRequest, Int) throws -> VyronResponsesTestResponse

    private var handler: Handler?
    private var automaticallyAnswerToolProbe = true
    private(set) var requests: [URLRequest] = []
    private(set) var stopCount = 0

    func reset(_ handler: Handler? = nil, automaticallyAnswerToolProbe: Bool = true) {
        self.handler = handler
        self.automaticallyAnswerToolProbe = automaticallyAnswerToolProbe
        requests = []
        stopCount = 0
    }

    func response(for request: URLRequest) throws -> VyronResponsesTestResponse {
        requests.append(request)
        if automaticallyAnswerToolProbe, let response = try toolProbeResponse(for: request) { return response }
        guard let handler else { throw URLError(.unsupportedURL) }
        return try handler(request, requests.count)
    }

    func stopped() { stopCount += 1 }

    private func toolProbeResponse(for request: URLRequest) throws -> VyronResponsesTestResponse? {
        guard request.url?.path == "/v1/responses", request.httpMethod == "POST" else { return nil }
        let body = try VyronResponsesTestSupport.body(request)
        guard (body["tool_choice"] as? [String: String])?["name"] == "vyron_check_tools" else { return nil }
        let prompt = try VyronResponsesTestSupport.json(body["input"] ?? [])
        guard let range = prompt.range(of: "nonce ") else { throw URLError(.cannotDecodeRawData) }
        let nonce = String(prompt[range.upperBound...].prefix(36))
        guard UUID(uuidString: nonce) != nil else { throw URLError(.cannotDecodeRawData) }
        return VyronResponsesTestResponse(body: try VyronResponsesTestSupport.completion([
            VyronResponsesTestSupport.toolOutput(
                "probe-call", name: "vyron_check_tools",
                arguments: try VyronResponsesTestSupport.json(["nonce": nonce])
            )
        ]))
    }
}
