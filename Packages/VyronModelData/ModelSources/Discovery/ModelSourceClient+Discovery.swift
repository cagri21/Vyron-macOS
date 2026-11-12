import Foundation

extension ModelSourceClient {
    public func discover(url: URL) async throws -> [ModelSourceVariant] {
        let source = try Self.validateSourceURL(url)
        let host = source.host?.lowercased() ?? ""
        if ["ollama.com", "www.ollama.com"].contains(host) { return try await ollamaVariants(source) }
        if ["huggingface.co", "www.huggingface.co", "hf.co"].contains(host) {
            return try await huggingFaceVariants(source)
        }
        guard source.pathExtension.lowercased() == "gguf" else { throw ModelSourceError.unsupportedSource }
        guard !Self.isSplitFile(source.lastPathComponent) else { throw ModelSourceError.splitGGUF }
        var request = URLRequest(url: source)
        request.httpMethod = VyronModelHTTP.head
        request.timeoutInterval = VyronModelSourceLimits.discoveryTimeout
        let (_, response) = try await sourceSession.data(for: request)
        try Task.checkCancellation()
        let http = response as? HTTPURLResponse
        // Some signed download services do not implement HEAD; the actual GET is verified during import.
        if let status = http?.statusCode, !(200..<300).contains(status), ![403, 405, 501].contains(status) {
            throw ModelSourceError.httpStatus(status)
        }
        let size =
            http.map { (200..<300).contains($0.statusCode) } == true && response.expectedContentLength > 0
            ? response.expectedContentLength : nil
        return [Self.fileVariant(name: source.lastPathComponent, url: source, size: size)]
    }

    public static func suggestedModelName(for variant: ModelSourceVariant) -> String {
        if let tag = variant.ollamaTag { return tag }
        let basename = (variant.name as NSString).lastPathComponent
        let withoutExtension = (basename as NSString).deletingPathExtension.lowercased()
        let cleaned = withoutExtension.replacingOccurrences(
            of: #"[^a-z0-9._-]+"#,
            with: "-",
            options: .regularExpression
        )
        .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        return String(cleaned.isEmpty ? "imported-model" : cleaned.prefix(150)) + ":latest"
    }

    private func ollamaVariants(_ source: URL) async throws -> [ModelSourceVariant] {
        let components = source.path.split(separator: "/").map(String.init)
        guard components.first == "library", (2...3).contains(components.count),
            components.count != 3 || components[2] == "tags"
        else { throw ModelSourceError.unsupportedSource }
        let family = String(components[1].split(separator: ":", maxSplits: 1)[0])
        guard family.range(of: #"\A[A-Za-z0-9][A-Za-z0-9._-]*\z"#, options: .regularExpression) != nil else {
            throw ModelSourceError.unsupportedSource
        }
        let tagsURL = URL(string: "https://ollama.com/library/\(family)/tags")!
        let (data, _) = try await metadata(URLRequest(url: tagsURL))
        guard let html = String(data: data, encoding: .utf8) else { throw ModelSourceError.invalidMetadata }
        let variants = try Self.parseOllamaTags(html: html, family: family)
        guard !variants.isEmpty else { throw ModelSourceError.noVariants }
        return variants
    }

    static func parseOllamaTags(html: String, family: String) throws -> [ModelSourceVariant] {
        // Read only literal published tag links. No script or remote markup is evaluated.
        let pattern = #"<a\b[^>]*href=["']/library/([^"'<>]+:[^"'<>]+)["'][^>]*>([\s\S]*?)</a>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(html.startIndex..., in: html)
        var variants: [ModelSourceVariant] = []
        var seen = Set<String>()
        for match in regex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range(at: 1), in: html),
                let innerRange = Range(match.range(at: 2), in: html)
            else { continue }
            let tag = String(html[tagRange]).removingPercentEncoding ?? String(html[tagRange])
            guard tag.hasPrefix(family + ":"), (try? OllamaClient.validateModelName(tag)) != nil,
                seen.insert(tag).inserted
            else { continue }
            let text = String(html[innerRange]).replacingOccurrences(
                of: #"<[^>]*>"#,
                with: " ",
                options: .regularExpression
            )
            variants.append(
                ModelSourceVariant(
                    id: tag,
                    name: tag,
                    ollamaTag: tag,
                    quantization: precision(in: tag),
                    parameterSize: parameterSize(in: tag),
                    sizeBytes: parseSize(text)
                )
            )
        }
        return variants.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func huggingFaceVariants(_ source: URL) async throws -> [ModelSourceVariant] {
        let encodedParts = (URLComponents(url: source, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? "")
            .split(separator: "/").map(String.init)
        let parts = encodedParts.map { $0.removingPercentEncoding ?? $0 }
        guard parts.count >= 2, !["datasets", "spaces", "api"].contains(parts[0]),
            parts[0].range(of: #"\A[A-Za-z0-9][A-Za-z0-9._-]*\z"#, options: .regularExpression) != nil,
            parts[1].range(of: #"\A[A-Za-z0-9][A-Za-z0-9._-]*\z"#, options: .regularExpression) != nil
        else { throw ModelSourceError.unsupportedSource }
        let owner = parts[0], repository = parts[1]
        var revision = "main"
        var folder = ""
        if parts.count > 2 {
            guard parts.count >= 4, ["tree", "resolve", "blob"].contains(parts[2]) else {
                throw ModelSourceError.unsupportedSource
            }
            revision = parts[3]
            if parts[2] == "tree", parts.count > 4 {
                folder = parts.dropFirst(4).map(Self.encodeComponent).joined(separator: "/")
            }
        }
        guard !revision.isEmpty, revision != ".", revision != ".." else { throw ModelSourceError.unsupportedSource }
        let apiRoot =
            "https://huggingface.co/api/models/\(Self.encodeComponent(owner))/\(Self.encodeComponent(repository))/tree/\(Self.encodeComponent(revision))"
        var next: URL? = URL(string: apiRoot + (folder.isEmpty ? "" : "/" + folder) + "?recursive=true&limit=1000")
        var variants: [ModelSourceVariant] = []
        var seen = Set<String>()
        var visited = Set<URL>()
        while let page = next {
            guard visited.count < 25, visited.insert(page).inserted else { throw ModelSourceError.metadataTooLarge }
            let (data, response) = try await metadata(URLRequest(url: page))
            let entries = try JSONDecoder().decode([HubFile].self, from: data)
            for entry in entries where entry.type == "file" && entry.path.lowercased().hasSuffix(".gguf") {
                guard !Self.isSplitFile(entry.path),
                    !(entry.path as NSString).lastPathComponent.lowercased().hasPrefix("mmproj")
                else { continue }
                let path = entry.path.split(separator: "/").map { Self.encodeComponent(String($0)) }.joined(
                    separator: "/"
                )
                guard
                    let download = URL(
                        string:
                            "https://huggingface.co/\(Self.encodeComponent(owner))/\(Self.encodeComponent(repository))/resolve/\(Self.encodeComponent(revision))/\(path)?download=true"
                    )
                else { continue }
                if seen.insert(download.absoluteString).inserted {
                    variants.append(Self.fileVariant(name: entry.path, url: download, size: entry.size))
                }
            }
            guard variants.count <= VyronModelSourceLimits.maximumVariants else { throw ModelSourceError.metadataTooLarge }
            next = Self.nextHubPage(response.value(forHTTPHeaderField: "Link"), prefix: apiRoot)
        }
        guard !variants.isEmpty else { throw ModelSourceError.noVariants }
        let preferred = source.lastPathComponent
        return variants.sorted {
            if ($0.name as NSString).lastPathComponent == preferred { return true }
            if ($1.name as NSString).lastPathComponent == preferred { return false }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func precision(in name: String) -> String? {
        let pattern =
            #"(?i)(?:^|[^a-z0-9])((?:IQ[1-4]|TQ[12]|Q[2-9])(?:_[a-z0-9]+)*|BF16|FP16|F16|FP32|F32|INT[48]|MXFP[48]|NVFP4)(?=$|[^a-z0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
            let range = Range(match.range(at: 1), in: name)
        else { return nil }
        return String(name[range]).uppercased()
    }

    static func parameterSize(in name: String) -> String? {
        let pattern = #"(?i)(?:^|[^a-z0-9])([0-9]+(?:\.[0-9]+)?[bm])(?=$|[^a-z0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
            let range = Range(match.range(at: 1), in: name)
        else { return nil }
        return String(name[range]).uppercased()
    }

    static func isSplitFile(_ name: String) -> Bool {
        name.range(of: #"(?i)-[0-9]{5}-of-[0-9]{5}\.gguf$"#, options: .regularExpression) != nil
    }

    private static func fileVariant(name: String, url: URL, size: Int64?) -> ModelSourceVariant {
        ModelSourceVariant(
            id: url.absoluteString,
            name: name,
            downloadURL: url,
            quantization: precision(in: name),
            parameterSize: parameterSize(in: name),
            sizeBytes: size
        )
    }

    private static func encodeComponent(_ component: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return component.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private static func nextHubPage(_ link: String?, prefix: String) -> URL? {
        guard let link else { return nil }
        for component in link.components(separatedBy: ",") where component.contains("rel=\"next\"") {
            guard let left = component.firstIndex(of: "<"), let right = component.firstIndex(of: ">"), left < right,
                let url = URL(string: String(component[component.index(after: left)..<right])),
                url.scheme == "https", url.host == "huggingface.co", url.absoluteString.hasPrefix(prefix),
                (try? validateSourceURL(url)) != nil
            else { continue }
            return url
        }
        return nil
    }

    private static func parseSize(_ text: String) -> Int64? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)([0-9]+(?:\.[0-9]+)?)\s*([KMGT])B\b"#),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let numberRange = Range(match.range(at: 1), in: text),
            let unitRange = Range(match.range(at: 2), in: text),
            let value = Double(text[numberRange]),
            let scale = ["K": 1_000.0, "M": 1_000_000.0, "G": 1_000_000_000.0, "T": 1_000_000_000_000.0][
                String(text[unitRange]).uppercased()
            ], value.isFinite, value >= 0, value * scale < Double(Int64.max)
        else { return nil }
        return Int64(value * scale)
    }
}
