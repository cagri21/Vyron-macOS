import CryptoKit
import Foundation
import VyronLocalization
import VyronModelDomain

extension ModelSourceClient {
    public func importModel(
        variant: ModelSourceVariant,
        name: String,
        onProgress: @escaping @Sendable (ModelPullProgress) -> Void
    ) async throws -> String {
        let tag = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try OllamaClient.validateModelName(tag)
        guard let source = variant.downloadURL, variant.ollamaTag == nil else {
            throw ModelSourceError.unsupportedSource
        }
        _ = try Self.validateSourceURL(source)
        guard source.pathExtension.lowercased() == "gguf" else { throw ModelSourceError.unsupportedSource }
        let filename = source.lastPathComponent
        guard !Self.isSplitFile(filename) else { throw ModelSourceError.splitGGUF }
        let endpoint = try Self.localImportEndpoint(ollamaEndpoint)
        var catalogRequest = URLRequest(url: endpoint.appendingPathComponent("api/tags"))
        catalogRequest.timeoutInterval = VyronModelSourceLimits.installedCatalogTimeout
        let (catalogData, _) = try await metadata(catalogRequest, using: importSession)
        let existing = try JSONDecoder().decode(ImportCatalog.self, from: catalogData)
        guard !existing.models.contains(where: { ModelCatalog.sameInstalledName($0.name, tag) }) else {
            throw ModelSourceError.importFailed(
                VyronModelDataText.sourceModelAlreadyExists
            )
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "vyron-model-import-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: temporary,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: temporary) }
        onProgress(ModelPullProgress(status: "Downloading GGUF", total: variant.sizeBytes, phase: .downloadingGGUF))
        var request = URLRequest(url: source)
        request.timeoutInterval = VyronModelSourceLimits.transferTimeout
        let download: URL
        let response: URLResponse
        if let downloadHandler {
            (download, response) = try await downloadHandler(request, onProgress)
        } else {
            let observer = ModelDownloadObserver(onProgress: onProgress)
            (download, response) = try await sourceSession.download(for: request, delegate: observer)
        }
        defer { try? FileManager.default.removeItem(at: download) }
        try Self.checkResponse(response)
        try Task.checkCancellation()
        let file = temporary.appendingPathComponent("model.gguf")
        try FileManager.default.moveItem(at: download, to: file)
        let actualSize =
            (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
        if let expected = variant.sizeBytes, expected > 0, actualSize != expected {
            throw ModelSourceError.invalidGGUF
        }
        onProgress(ModelPullProgress(
            status: "Verifying GGUF", completed: actualSize, total: actualSize, phase: .verifyingGGUF
        ))
        let digest = try Self.digestGGUF(file)
        try Task.checkCancellation()
        var upload = URLRequest(url: endpoint.appendingPathComponent("api/blobs/\(digest)"))
        upload.httpMethod = VyronModelHTTP.post
        upload.setValue(VyronModelHTTP.binary, forHTTPHeaderField: VyronModelHTTP.contentTypeHeader)
        upload.timeoutInterval = VyronModelSourceLimits.transferTimeout
        onProgress(ModelPullProgress(status: "Importing model weights into Ollama", phase: .importingModelWeights))
        let (uploadBody, uploadResponse) = try await importSession.upload(for: upload, fromFile: file)
        try Self.checkResponse(uploadResponse)
        guard uploadBody.count <= VyronModelSourceLimits.maximumImportResponseBytes else {
            throw ModelSourceError.invalidMetadata
        }
        try Task.checkCancellation()
        var create = URLRequest(url: endpoint.appendingPathComponent("api/create"))
        create.httpMethod = VyronModelHTTP.post
        create.setValue(VyronModelHTTP.json, forHTTPHeaderField: VyronModelHTTP.contentTypeHeader)
        create.httpBody = try JSONEncoder().encode(ImportRequest(model: tag, files: [filename: digest]))
        create.timeoutInterval = VyronModelSourceLimits.transferTimeout
        let (bytes, createResponse) = try await importSession.bytes(for: create)
        defer { bytes.task.cancel() }
        try Self.checkResponse(createResponse)
        var success = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard line.utf8.count <= VyronModelSourceLimits.maximumImportResponseBytes,
                let data = line.data(using: .utf8)
            else {
                throw ModelSourceError.invalidMetadata
            }
            let status = try JSONDecoder().decode(ImportStatus.self, from: data)
            if status.error != nil {
                throw ModelSourceError.importFailed(
                    VyronModelDataText.sourceArchitectureRejected
                )
            }
            if let value = status.status {
                onProgress(ModelPullProgress(status: value, phase: VyronOllamaProgressStatus.phase(for: value)))
                if value == VyronOllamaProgressStatus.success { success = true; break }
            }
        }
        guard success else { throw ModelSourceError.importFailed(VyronModelDataText.sourceImportIncomplete) }
        try Task.checkCancellation()
        return tag.contains(":") ? tag : tag + ":latest"
    }

    static func digestGGUF(_ url: URL) throws -> String {
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 24), header.count == 24,
            Array(header.prefix(4)) == Array("GGUF".utf8),
            [UInt8(2), UInt8(3)].contains(header[4]), header[5...7].allSatisfy({ $0 == 0 })
        else { throw ModelSourceError.invalidGGUF }
        var hash = SHA256()
        hash.update(data: header)
        while let data = try handle.read(upToCount: VyronModelSourceLimits.digestChunkBytes), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return "sha256:" + hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func localImportEndpoint(_ url: URL) throws -> URL {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme?.lowercased() == VyronModelEndpointPolicy.insecureScheme,
            VyronModelEndpointPolicy.localOllamaHosts.contains(parts.host?.lowercased() ?? ""),
            parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
            parts.path.isEmpty || parts.path == "/",
            parts.port.map(VyronModelEndpointPolicy.validPorts.contains) ?? true
        else { throw ModelSourceError.invalidLocalEndpoint }
        return url
    }
}
