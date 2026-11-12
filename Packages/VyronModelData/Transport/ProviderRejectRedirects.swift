import Foundation

package final class ProviderRejectRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    package override init() { super.init() }

    package func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
