import Foundation
import VyronModelDomain

final class ModelDownloadObserver: ModelSourceRedirectDelegate, URLSessionDownloadDelegate,
    @unchecked Sendable {
    let onProgress: @Sendable (ModelPullProgress) -> Void

    init(onProgress: @escaping @Sendable (ModelPullProgress) -> Void) { self.onProgress = onProgress }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(
            ModelPullProgress(
                status: "Downloading GGUF",
                completed: totalBytesWritten,
                total: totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil,
                phase: .downloadingGGUF
            )
        )
    }
}
