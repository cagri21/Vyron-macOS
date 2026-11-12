import Foundation
import VyronDevelopment

/// Drives only the standalone local Office API. It never starts a Harness agent or loads API keys.
public struct VyronOfficeRuntime: Sendable {
    private let configuration: VyronOfficeConfiguration
    private let run: @Sendable (VyronOfficeProcessRequest) async throws -> CommandResult

    public init(configuration: VyronOfficeConfiguration) {
        self.configuration = configuration
        self.run = VyronOfficeProtectedProcess.run
    }

    init(
        configuration: VyronOfficeConfiguration,
        run: @escaping @Sendable (VyronOfficeProcessRequest) async throws -> CommandResult
    ) {
        self.configuration = configuration
        self.run = run
    }

    public func status() async throws -> VyronOfficeRuntimeStatus {
        let executable: URL
        do { executable = try configuration.resolvedExecutable() } catch {
            return VyronOfficeRuntimeStatus(
                isAvailable: false, message: VyronOfficeConfiguration.setupMessage, pythonExecutable: nil
            )
        }
        return try await withScratch { directory in
            let response = try await invoke(.status, executable: executable, directory: directory)
            return VyronOfficeRuntimeStatus(
                isAvailable: response.ok,
                message: response.ok
                    ? "Local Office conversion, document rendering and spreadsheet recalculation are available."
                    : failureMessage(response.code),
                pythonExecutable: executable.path
            )
        }
    }

    func process(_ request: VyronOfficeRuntimeRequest) async throws -> VyronOfficeProcessingResult {
        let executable = try configuration.resolvedExecutable()
        return try await withScratch { directory in
            let input = directory.appendingPathComponent("input." + request.input.fileExtension)
            try request.input.data.write(to: input, options: .withoutOverwriting)
            let response = try await invoke(
                request.operation, executable: executable, directory: directory, pages: request.pages
            )
            guard response.ok, let names = response.files, !names.isEmpty,
                names.count <= VyronOfficeLimits.maximumPages, Set(names).count == names.count,
                expectedOutput(names, operation: request.operation)
            else { throw VyronOfficeError(message: failureMessage(response.code)) }
            let output = directory.appendingPathComponent("output", isDirectory: true)
            var total = 0
            let artifacts = try names.map { name in
                guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains("\\"),
                    !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
                else { throw invalidOutput() }
                let url = output.appendingPathComponent(name)
                let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard metadata.isRegularFile == true, metadata.isSymbolicLink != true,
                    let size = metadata.fileSize, size > 0,
                    size <= VyronOfficeLimits.maximumOutputBytes - total
                else { throw invalidOutput() }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                total += data.count
                guard total <= VyronOfficeLimits.maximumOutputBytes, validHeader(data, operation: request.operation) else {
                    throw invalidOutput()
                }
                return VyronOfficeArtifact(name: name, data: data)
            }
            let warnings = Array((response.warnings ?? []).prefix(20)).map { warning in
                String(warning.filter { character in
                    !character.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
                }.prefix(300))
            }
            return VyronOfficeProcessingResult(artifacts: artifacts, warnings: warnings)
        }
    }

    private func invoke(
        _ operation: VyronOfficeOperation, executable: URL, directory: URL, pages: [Int] = []
    ) async throws -> VyronOfficeRuntimeResponse {
        let packaged = Bundle.main.resourceURL?
            .appendingPathComponent("Vyron_VyronCore.bundle", isDirectory: true)
        let helper = packaged.flatMap { Bundle(url: $0)?.url(forResource: "vyron_office", withExtension: "py") }
            ?? Bundle.module.url(forResource: "vyron_office", withExtension: "py")
        guard let helper else {
            throw VyronOfficeError(message: "The bundled Office helper is missing. Rebuild or reinstall Vyron.")
        }
        var arguments = ["-I", "-B", helper.path, operation.rawValue, directory.path]
        let cache = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/deepseek-harness/resources", isDirectory: true)
        arguments += ["--resource-cache", cache.path]
        if !pages.isEmpty { arguments += ["--pages", pages.map(String.init).joined(separator: ",")] }
        let result = try await run(VyronOfficeProcessRequest(
            executable: executable, arguments: arguments, directory: directory
        ))
        try Task.checkCancellation()
        guard !result.timedOut else {
            throw VyronOfficeError(message: "Local Office processing exceeded its two-minute limit. No output was published.")
        }
        guard !result.truncated, let line = result.output.components(separatedBy: .newlines).last(where: {
            $0.hasPrefix("VYRON_OFFICE_RESULT ")
        }), let data = String(line.dropFirst("VYRON_OFFICE_RESULT ".count)).data(using: .utf8) else {
            throw VyronOfficeError(message: "The local Office runtime did not return a valid result. "
                + VyronOfficeConfiguration.setupMessage)
        }
        let response = try JSONDecoder().decode(VyronOfficeRuntimeResponse.self, from: data)
        guard result.exitCode == 0 || !response.ok else {
            throw VyronOfficeError(message: "The local Office runtime stopped before confirming its output.")
        }
        return response
    }

    private func withScratch<T: Sendable>(
        _ operation: @Sendable (URL) async throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronOffice-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
        )
        let value: T
        do { value = try await operation(directory) } catch {
            let original = error
            do { try FileManager.default.removeItem(at: directory) } catch {
                throw VyronOfficeError(message: "Office processing stopped and its temporary files could not be removed. "
                    + "Check the temporary folder at " + directory.path)
            }
            throw original
        }
        try FileManager.default.removeItem(at: directory)
        try Task.checkCancellation()
        return value
    }

    private func failureMessage(_ code: String) -> String {
        switch code {
        case "missing_module":
            "The selected Python does not include deepseek-harness-sdk. " + VyronOfficeConfiguration.setupMessage
        case "missing_office":
            "The local Office sidecar has not been prepared for this Python installation. "
                + VyronOfficeConfiguration.setupMessage
        case "operation_failed":
            "The local Office engine could not process this document. Check its format and local runtime setup."
        default: "The local Office helper returned an invalid or unsupported result."
        }
    }

    private func invalidOutput() -> VyronOfficeError {
        VyronOfficeError(message: "The local Office engine returned unsafe, missing or oversized output.")
    }

    private func expectedOutput(_ names: [String], operation: VyronOfficeOperation) -> Bool {
        switch operation {
        case .convert: names == ["document.pdf"]
        case .recalculate: names == ["workbook.xlsx"]
        case .render: names.allSatisfy { URL(fileURLWithPath: $0).pathExtension.lowercased() == "png" }
        case .status: false
        }
    }

    private func validHeader(_ data: Data, operation: VyronOfficeOperation) -> Bool {
        switch operation {
        case .convert: data.starts(with: Data("%PDF-".utf8))
        case .recalculate: data.starts(with: [0x50, 0x4B, 0x03, 0x04])
        case .render: data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        case .status: false
        }
    }
}
