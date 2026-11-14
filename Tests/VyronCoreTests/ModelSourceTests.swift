import CryptoKit
import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

private final class SourceStubState: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (URLRequest) throws -> (Int, [String: String], Data))?
    func set(_ value: (@Sendable (URLRequest) throws -> (Int, [String: String], Data))?) { lock.withLock { handler = value } }
    func reply(_ request: URLRequest) throws -> (Int, [String: String], Data) {
        let callback = lock.withLock { handler }
        guard let callback else { throw URLError(.unsupportedURL) }
        return try callback(request)
    }
}

private final class SourceStubProtocol: URLProtocol, @unchecked Sendable {
    static let state = SourceStubState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.state.reply(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class SourceValues<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []
    func append(_ value: Value) { lock.withLock { storage.append(value) } }
    var values: [Value] { lock.withLock { storage } }
}

final class ModelSourceTests: XCTestCase, @unchecked Sendable {
    override func tearDown() { SourceStubProtocol.state.set(nil); super.tearDown() }

    private func client(endpoint: String = "http://127.0.0.1:11434", download: ModelSourceClient.DownloadHandler? = nil) -> ModelSourceClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SourceStubProtocol.self]
        return ModelSourceClient(ollamaEndpoint: URL(string: endpoint)!, configuration: configuration, downloadHandler: download)
    }

    func testSourceURLValidationRejectsCredentialsAndInsecureRemoteSources() throws {
        for value in ["https://models.example/model.gguf?download=true", "http://localhost:9000/model.gguf", "http://127.0.0.1:9000/model.gguf"] {
            XCTAssertEqual(try ModelSourceClient.validateSourceURL(URL(string: value)!).absoluteString, value)
        }
        for value in ["http://models.example/model.gguf", "https://user:secret@models.example/model.gguf", "file:///tmp/model.gguf", "https://models.example/model.gguf#fragment", "https://models.example:0/model.gguf"] {
            XCTAssertThrowsError(try ModelSourceClient.validateSourceURL(URL(string: value)!)) { XCTAssertEqual($0 as? ModelSourceError, .invalidURL) }
        }
    }

    func testOllamaVariantsReadOnlyPublishedLinksAndKeepExactTags() throws {
        let html = """
        <a href="/library/example:7b-q4_K_M"><span>example:7b-q4_K_M</span><span>4.7GB</span></a>
        <a href="/library/example:7b-q4_K_M">duplicate desktop link</a>
        <a href="/library/example:7b-q8_0"><span>8.1GB</span></a>
        <a href="/library/example:latest"><span>4.7GB</span></a>
        <a href="/library/other:7b-q2_K">not this model</a>
        <a href="/library/example:7b-cloud">remote-backed tag</a>
        <script>const guessedTags = ['example:7b-fp16'];</script>
        """
        let variants = try ModelSourceClient.parseOllamaTags(html: html, family: "example")
        XCTAssertEqual(variants.map(\.ollamaTag), ["example:7b-q4_K_M", "example:7b-q8_0", "example:latest"])
        XCTAssertEqual(variants[0].quantization, "Q4_K_M")
        XCTAssertEqual(variants[0].parameterSize, "7B")
        XCTAssertEqual(variants[0].sizeBytes, 4_700_000_000)
        XCTAssertNil(variants[2].quantization, "Alias precision must not be invented")
        XCTAssertNil(variants[0].downloadURL)
    }

    func testPrecisionNamesIncludeActualSubvariantsWithoutGuessing() {
        XCTAssertEqual(ModelSourceClient.precision(in: "Code-7B-IQ3_XXS.gguf"), "IQ3_XXS")
        XCTAssertEqual(ModelSourceClient.precision(in: "model:8b-q4_K_M"), "Q4_K_M")
        XCTAssertEqual(ModelSourceClient.precision(in: "Model-F16.gguf"), "F16")
        XCTAssertEqual(ModelSourceClient.precision(in: "Model-NVFP4.gguf"), "NVFP4")
        XCTAssertNil(ModelSourceClient.precision(in: "Qwen3-8B.gguf"))
        XCTAssertNil(ModelSourceClient.precision(in: "model:latest"))
        XCTAssertEqual(ModelSourceClient.parameterSize(in: "Qwen-0.6B-Q8_0.gguf"), "0.6B")
    }

    func testInstalledPrecisionDiscoveryKeepsModelSizeAndTuning() async throws {
        SourceStubProtocol.state.set { request in
            XCTAssertEqual(request.url?.absoluteString, "https://ollama.com/library/qwen3.8/tags")
            let html = """
            <a href="/library/qwen3.8:27b">18 GB</a>
            <a href="/library/qwen3.8:27b-q4_K_M">18 GB</a>
            <a href="/library/qwen3.8:27b-mxfp8">30 GB</a>
            <a href="/library/qwen3.8:27b-q8_0">30 GB</a>
            <a href="/library/qwen3.8:27b-mtp-q8_0">30 GB</a>
            <a href="/library/qwen3.8:27b-dflash2-nvfp4">30 GB</a>
            <a href="/library/qwen3.8:27b-q8_0_instruct">30 GB</a>
            <a href="/library/qwen3.8:27b-q8_0-cloud">30 GB</a>
            <a href="/library/qwen3.8:35b-q8_0">40 GB</a>
            """
            return (200, [:], Data(html.utf8))
        }
        let source = client()
        let model = LocalModel(name: "library/qwen3.8:27b-q4_K_M", size: 18_000_000_000, parameterSize: "27.3B")
        let variants = try await source.discoverPrecisionVariants(for: model)
        XCTAssertEqual(variants.map(\.ollamaTag), ["qwen3.8:27b-mxfp8", "qwen3.8:27b-q8_0"])

        let alias = LocalModel(name: "qwen3.8:latest", size: model.size, parameterSize: "27.3B")
        let aliasVariants = try await source.discoverPrecisionVariants(for: alias)
        XCTAssertEqual(aliasVariants.map(\.ollamaTag), ["qwen3.8:27b-mxfp8", "qwen3.8:27b-q4_K_M", "qwen3.8:27b-q8_0"])
    }

    func testInstalledPrecisionDiscoveryRejectsUnknownAliasesAndUnofficialSourcesWithoutTransport() async throws {
        SourceStubProtocol.state.set { _ in
            XCTFail("No transport expected")
            throw URLError(.unsupportedURL)
        }
        for name in ["owner/example:7b", "example-cloud:7b", "example:latest"] {
            let model = LocalModel(name: name, size: 42)
            XCTAssertFalse(ModelSourceClient.canDiscoverPrecisionVariants(for: model))
            let variants = try await client().discoverPrecisionVariants(for: model)
            XCTAssertTrue(variants.isEmpty)
        }
    }

    func testInstalledPrecisionAlternatesMatchSameLocalNamespaceAndTuning() {
        let current = LocalModel(name: "owner/example:instruct-q4_K_M", size: 40, parameterSize: "7B")
        let variants = ModelSourceClient.installedPrecisionVariants(for: current, among: [
            current,
            LocalModel(name: "owner/example:instruct-q8_0", size: 80, parameterSize: "7B"),
            LocalModel(name: "owner/example:instruct-fp16", size: 160, parameterSize: "8B"),
            LocalModel(name: "owner/example:base-q8_0", size: 80, parameterSize: "7B"),
            LocalModel(name: "other/example:instruct-q8_0", size: 80, parameterSize: "7B"),
            LocalModel(name: "owner/example:instruct-q8_0-cloud", size: 80, parameterSize: "7B")
        ])

        XCTAssertEqual(variants.map(\.ollamaTag), ["owner/example:instruct-q8_0"])
        XCTAssertEqual(variants.map(\.quantization), ["Q8_0"])
        XCTAssertEqual(variants.map(\.sizeBytes), [80])
    }

    func testHuggingFaceDiscoveryFollowsPaginationAndPreservesEncodedRevision() async throws {
        let requests = SourceValues<String>()
        SourceStubProtocol.state.set { request in
            let url = request.url!.absoluteString
            requests.append(url)
            XCTAssertTrue(url.contains("tree/feature%2Ftest/folder"))
            if url.contains("cursor=next") {
                return (200, [:], Data(#"[{"type":"file","path":"folder/Code-7B-Q8_0.gguf","size":8000},{"type":"file","path":"folder/Code-7B-Q4_K_M.gguf","size":4000}]"#.utf8))
            }
            return (200, ["Link": "<https://huggingface.co/api/models/owner/repo/tree/feature%2Ftest/folder?recursive=true&cursor=next>; rel=\"next\""], Data(#"[{"type":"file","path":"folder/Code-7B-Q4_K_M.gguf","size":4000},{"type":"file","path":"README.md","size":50},{"type":"file","path":"mmproj-Model-F16.gguf","size":100},{"type":"file","path":"folder/Code-Q8_0-00001-of-00002.gguf","size":9000}]"#.utf8))
        }
        let variants = try await client().discover(url: URL(string: "https://huggingface.co/owner/repo/tree/feature%2Ftest/folder")!)
        XCTAssertEqual(requests.values.count, 2)
        XCTAssertEqual(variants.count, 2)
        XCTAssertEqual(variants.map(\.quantization), ["Q4_K_M", "Q8_0"])
        XCTAssertEqual(variants.map(\.sizeBytes), [4000, 8000])
        XCTAssertEqual(variants[0].downloadURL?.absoluteString, "https://huggingface.co/owner/repo/resolve/feature%2Ftest/folder/Code-7B-Q4_K_M.gguf?download=true")
    }

    func testResolveAndBlobLinksDiscoverOtherAvailableBitOptions() async throws {
        SourceStubProtocol.state.set { request in
            XCTAssertTrue(request.url!.absoluteString.contains("/tree/release?"))
            return (200, [:], Data(#"[{"type":"file","path":"Code-Q4_K_M.gguf","size":40},{"type":"file","path":"Code-Q8_0.gguf","size":80}]"#.utf8))
        }
        for mode in ["resolve", "blob"] {
            let variants = try await client().discover(url: URL(string: "https://huggingface.co/owner/repo/\(mode)/release/Code-Q8_0.gguf?download=true")!)
            XCTAssertEqual(variants.count, 2)
            XCTAssertEqual(variants.first?.quantization, "Q8_0")
        }
    }

    func testDirectGGUFSupportsSignedQueriesAndUnknownHeadSize() async throws {
        SourceStubProtocol.state.set { request in
            XCTAssertEqual(request.httpMethod, "HEAD")
            XCTAssertEqual(request.url?.query, "signature=example")
            return (405, ["Content-Length": "12"], Data())
        }
        let variants = try await client().discover(url: URL(string: "https://models.example/Model-8B-Q5_K_M.gguf?signature=example")!)
        XCTAssertEqual(variants.count, 1)
        XCTAssertEqual(variants[0].quantization, "Q5_K_M")
        XCTAssertNil(variants[0].sizeBytes, "HEAD failure body size is not the model size")
    }

    func testUnsupportedSourcesAndSplitFilesFailBeforeTransport() async throws {
        SourceStubProtocol.state.set { _ in XCTFail("No transport expected"); throw URLError(.unsupportedURL) }
        for value in ["https://example.com/model.safetensors", "https://example.com/Model-Q8_0-00001-of-00002.gguf"] {
            do { _ = try await client().discover(url: URL(string: value)!); XCTFail("Expected invalid model source") }
            catch { XCTAssertTrue([ModelSourceError.unsupportedSource, .splitGGUF].contains(error as? ModelSourceError ?? .invalidMetadata)) }
        }
    }

    func testMetadataResponsesAreBoundedAndErrorsDoNotExposeURLs() async throws {
        SourceStubProtocol.state.set { _ in (200, ["Content-Length": "999999999"], Data()) }
        do { _ = try await client().discover(url: URL(string: "https://huggingface.co/owner/repo")!); XCTFail("Expected size limit") }
        catch { XCTAssertEqual(error as? ModelSourceError, .metadataTooLarge) }
        SourceStubProtocol.state.set { _ in (401, [:], Data("secret token detail".utf8)) }
        do { _ = try await client().discover(url: URL(string: "https://huggingface.co/owner/repo")!); XCTFail("Expected auth failure") }
        catch { XCTAssertEqual(error as? ModelSourceError, .httpStatus(401)); XCTAssertFalse(error.localizedDescription.contains("secret")) }
    }

    func testGGUFHeaderAndDigestRejectHTMLAndHashUsingFileChunks() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("<html>not model weights</html>".utf8).write(to: file)
        XCTAssertThrowsError(try ModelSourceClient.digestGGUF(file)) { XCTAssertEqual($0 as? ModelSourceError, .invalidGGUF) }
        let weights = Self.ggufFixture()
        try weights.write(to: file)
        let expected = "sha256:" + SHA256.hash(data: weights).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(try ModelSourceClient.digestGGUF(file), expected)
    }

    func testImportUploadsVerifiedFileAndRequiresCreateSuccess() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let weights = Self.ggufFixture()
        try weights.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let expected = "sha256:" + SHA256.hash(data: weights).map { String(format: "%02x", $0) }.joined()
        let requests = SourceValues<String>()
        let updates = SourceValues<String>()
        SourceStubProtocol.state.set { request in
            requests.append(request.url!.path)
            if request.url!.path == "/api/tags" { return (200, [:], Data(#"{"models":[]}"#.utf8)) }
            XCTAssertEqual(request.httpMethod, "POST")
            if request.url!.path.hasPrefix("/api/blobs/") {
                XCTAssertEqual(request.url!.lastPathComponent, expected)
                return (201, [:], Data())
            }
            XCTAssertEqual(request.url!.path, "/api/create")
            let body = try JSONSerialization.jsonObject(with: Self.body(request)) as! [String: Any]
            XCTAssertEqual(body["model"] as? String, "my-coder:q4")
            XCTAssertEqual(body["files"] as? [String: String], ["Code-7B-Q4_K_M.gguf": expected])
            return (200, [:], Data("{\"status\":\"parsing GGUF\"}\n{\"status\":\"success\"}\n".utf8))
        }
        let importer = client(download: { request, progress in
            XCTAssertEqual(request.url?.lastPathComponent, "Code-7B-Q4_K_M.gguf")
            progress(ModelPullProgress(status: "Downloading GGUF", completed: Int64(weights.count), total: Int64(weights.count)))
            return (file, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let variant = ModelSourceVariant(id: "test", name: "Code-7B-Q4_K_M.gguf", downloadURL: URL(string: "https://example.com/Code-7B-Q4_K_M.gguf")!, sizeBytes: Int64(weights.count))
        let name = try await importer.importModel(variant: variant, name: "my-coder:q4") { updates.append($0.status) }
        XCTAssertEqual(name, "my-coder:q4")
        XCTAssertEqual(requests.values, ["/api/tags", "/api/blobs/" + expected, "/api/create"])
        XCTAssertTrue(updates.values.contains("Verifying GGUF"))
        XCTAssertEqual(updates.values.last, "success")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "Temporary weights should be cleaned after import")
    }

    func testBadDownloadAndRemoteImportEndpointNeverUpload() async throws {
        SourceStubProtocol.state.set { request in
            if request.url!.path == "/api/tags" { return (200, [:], Data(#"{"models":[]}"#.utf8)) }
            XCTFail("Invalid files/endpoints must never upload"); throw URLError(.unsupportedURL)
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("This is not GGUF model data".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let variant = ModelSourceVariant(id: "test", name: "model.gguf", downloadURL: URL(string: "https://example.com/model.gguf")!)
        let importer = client(download: { request, _ in (file, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!) })
        do { _ = try await importer.importModel(variant: variant, name: "model") { _ in }; XCTFail("Expected GGUF rejection") }
        catch { XCTAssertEqual(error as? ModelSourceError, .invalidGGUF) }
        let remote = client(endpoint: "https://ollama.example", download: { _, _ in XCTFail("Remote endpoint must fail before download"); throw URLError(.unsupportedURL) })
        do { _ = try await remote.importModel(variant: variant, name: "model") { _ in }; XCTFail("Expected local-only import") }
        catch { XCTAssertEqual(error as? ModelSourceError, .invalidLocalEndpoint) }
    }

    func testDuplicateLocalModelAliasFailsBeforeDownloading() async throws {
        SourceStubProtocol.state.set { request in
            XCTAssertEqual(request.url?.path, "/api/tags")
            return (200, [:], Data(#"{"models":[{"name":"library/my-coder:latest"}]}"#.utf8))
        }
        let importer = client(download: { _, _ in XCTFail("Existing model names must not download or overwrite"); throw URLError(.unsupportedURL) })
        let variant = ModelSourceVariant(id: "test", name: "model.gguf", downloadURL: URL(string: "https://example.com/model.gguf")!)
        do { _ = try await importer.importModel(variant: variant, name: "my-coder") { _ in }; XCTFail("Expected duplicate name rejection") }
        catch {
            guard case .importFailed(let detail) = error as? ModelSourceError else { return XCTFail("Expected helpful duplicate model error") }
            XCTAssertTrue(detail.contains("Choose another name"))
        }
    }

    func testSuggestedNamesAreValidLocalTags() throws {
        let variant = ModelSourceVariant(id: "test", name: "folder/My New Coder-7B-Q4_K_M.gguf")
        let name = ModelSourceClient.suggestedModelName(for: variant)
        XCTAssertEqual(name, "my-new-coder-7b-q4_k_m:latest")
        XCTAssertNoThrow(try OllamaClient.validateModelName(name))
    }

    private static func ggufFixture() -> Data { Data(Array("GGUF".utf8) + [3, 0, 0, 0] + [UInt8](repeating: 0, count: 24)) }
    private static func body(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
