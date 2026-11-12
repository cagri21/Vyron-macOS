import Foundation
import VyronLocalization
import VyronModelDomain

struct VyronOpenAIResponsesTokenCounter {
    let session: URLSession
    let request: URLRequest

    func count() async throws -> Int {
        try Task.checkCancellation()
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.missingHTTPResponse)
        }
        guard (200..<300).contains(http.statusCode) else { throw ModelProviderError.http(http.statusCode) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < VyronOpenAIResponsesLimits.tokenCountResponseBytes else {
                throw ModelProviderError.invalidResponse(VyronModelDataText.inputTokenResponseTooLarge)
            }
            data.append(byte)
        }
        try Task.checkCancellation()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(VyronOpenAIResponsesTokenCount.self, from: data).validated()
    }
}
