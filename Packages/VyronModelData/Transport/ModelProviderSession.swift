import Foundation
import VyronLocalization
import VyronModelDomain

func modelProviderSession(configuration: URLSessionConfiguration) -> URLSession {
    configuration.urlCache = nil
    configuration.httpShouldSetCookies = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = VyronModelProviderSessionPolicy.requestTimeout
    configuration.timeoutIntervalForResource = VyronModelProviderSessionPolicy.resourceTimeout
    return URLSession(configuration: configuration, delegate: ProviderRejectRedirects(), delegateQueue: nil)
}

func normalizedProviderError(_ error: Error) -> Error {
    if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
        return CancellationError()
    }
    if error is URLError { return ModelProviderError.connectionFailed }
    if error is DecodingError { return ModelProviderError.invalidResponse(VyronModelDataText.malformedJSON) }
    return error
}
