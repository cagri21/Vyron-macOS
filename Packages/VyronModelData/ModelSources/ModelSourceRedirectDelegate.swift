import Foundation

class ModelSourceRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url, (try? ModelSourceClient.validateSourceURL(url)) != nil,
            response.url?.scheme?.lowercased() != "https" || url.scheme?.lowercased() == "https"
        else {
            completionHandler(nil)
            return
        }
        var redirected = request
        // Public source downloads never forward credentials to a CDN or another host.
        redirected.setValue(nil, forHTTPHeaderField: VyronModelHTTP.authorizationHeader)
        redirected.setValue(nil, forHTTPHeaderField: VyronModelHTTP.cookieHeader)
        completionHandler(redirected)
    }
}
