import Foundation
import VyronDevelopment

public actor VyronOfficeTools {
    private var workspace: VyronOfficeWorkspace
    private let runtime: VyronOfficeRuntime
    private var processing = false

    public init(workspace: DevelopmentWorkspace, configuration: VyronOfficeConfiguration = .init()) {
        self.workspace = VyronOfficeWorkspace(rootURL: workspace.rootURL)
        self.runtime = VyronOfficeRuntime(configuration: configuration)
    }

    init(rootURL: URL, runtime: VyronOfficeRuntime) {
        self.workspace = VyronOfficeWorkspace(rootURL: rootURL)
        self.runtime = runtime
    }

    public func useWorkspace(_ workspace: DevelopmentWorkspace) throws {
        guard !processing else {
            throw VyronOfficeError(message: "Wait for Office processing to finish before changing its project.")
        }
        self.workspace = VyronOfficeWorkspace(rootURL: workspace.rootURL)
    }

    public nonisolated static let definitions: [DevelopmentExternalTool] = [
        DevelopmentExternalTool(
            name: "office_status",
            description: "Check the configured local Office runtime without downloading anything or using an API key. "
                + "Native PDF page rendering is available even when the optional Office runtime is missing.",
            inputSchema: schema(properties: [:], required: []), isReadOnly: true
        ),
        DevelopmentExternalTool(
            name: "office_convert",
            description: "Convert a project DOCX, PPTX, XLSX or other supported Office file into a new PDF locally. "
                + "Use relative input_path and output_path; the parent output folder must already exist. "
                + "Never overwrites files. Requires native review and an installed Office runtime; never downloads one.",
            inputSchema: schema(properties: paths, required: ["input_path", "output_path"]), isReadOnly: false
        ),
        DevelopmentExternalTool(
            name: "office_render",
            description: "Render PDF or Office pages to PNG files in a new project folder. Native PDF rendering needs "
                + "no extra runtime; Office inputs need the configured local Office runtime. "
                + "Use relative input_path/output_path; output_path is a new directory with an existing parent. "
                + "Optional pages are 1-based, unique, at most 20. Defaults to the first six PDF pages or first Office page. "
                + "Requires native review. Existing files and folders are preserved.",
            inputSchema: schema(properties: paths.merging([
                "pages": .object([
                    "type": .string("array"), "minItems": .number(1), "maxItems": .number(20),
                    "uniqueItems": .bool(true), "items": .object([
                        "type": .string("integer"), "minimum": .number(1), "maximum": .number(10_000)
                    ])
                ])
            ], uniquingKeysWith: { _, new in new }), required: ["input_path", "output_path"]), isReadOnly: false
        ),
        DevelopmentExternalTool(
            name: "office_recalculate",
            description: "Recalculate formulas in a project XLSX workbook and save a new XLSX locally using the "
                + "configured Office runtime. Use relative input_path/output_path with an existing parent folder. "
                + "Requires native review. Never overwrites input or output and never downloads dependencies. "
                + "Recalculation does not verify formula business logic or full Excel compatibility.",
            inputSchema: schema(properties: paths, required: ["input_path", "output_path"]), isReadOnly: false
        )
    ]

    public nonisolated static func handles(_ call: DevelopmentToolCall) -> Bool {
        definitions.contains { $0.name == call.function.name }
    }

    public func execute(_ call: DevelopmentToolCall) async throws -> DevelopmentExternalResult {
        try Task.checkCancellation()
        guard !processing else {
            return DevelopmentExternalResult(text: "Another local Office operation is still running.", isError: true)
        }
        processing = true
        defer { processing = false }
        do {
            if call.function.name == "office_status" {
                guard call.function.arguments.isEmpty else {
                    throw VyronOfficeError(message: "office_status takes no arguments.")
                }
                let status = try await runtime.status()
                let data = try JSONEncoder().encode(status)
                return DevelopmentExternalResult(text: String(decoding: data, as: UTF8.self))
            }
            let request = try VyronOfficeToolRequest(call: call)
            let project = workspace
            try project.validateDestination(path: request.outputPath)
            let data = try project.snapshot(path: request.inputPath)
            let fileExtension = URL(fileURLWithPath: request.inputPath).pathExtension.lowercased()
            let processed: VyronOfficeProcessingResult
            if request.operation == .render, fileExtension == "pdf" {
                processed = VyronOfficeProcessingResult(
                    artifacts: try VyronOfficePDFRenderer.render(data, pages: request.pages), warnings: []
                )
            } else {
                processed = try await runtime.process(VyronOfficeRuntimeRequest(
                    operation: request.operation, input: VyronOfficeInput(data: data, fileExtension: fileExtension),
                    pages: request.pages.isEmpty && request.operation == .render ? [1] : request.pages
                ))
            }
            try Task.checkCancellation()
            let paths = try project.publish(VyronOfficePublication(
                path: request.outputPath, artifacts: processed.artifacts, isDirectory: request.operation == .render
            ))
            let output = paths.map { project.rootURL.appendingPathComponent($0).path }.joined(separator: "\n")
            return DevelopmentExternalResult(text: "Created local Office output:\n" + output
                + (processed.warnings.isEmpty ? "" : "\nWarnings:\n" + processed.warnings.joined(separator: "\n"))
                + "\nThe original file was preserved. These binary artifacts are separate from source-edit revert history.")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return DevelopmentExternalResult(text: error.localizedDescription, isError: true)
        }
    }

    private nonisolated static var paths: [String: DevelopmentJSONValue] {
        let string: DevelopmentJSONValue = .object(["type": .string("string")])
        return ["input_path": string, "output_path": string]
    }

    private nonisolated static func schema(
        properties: [String: DevelopmentJSONValue], required: [String]
    ) -> [String: DevelopmentJSONValue] {
        ["type": .string("object"), "properties": .object(properties),
         "required": .array(required.map(DevelopmentJSONValue.string)), "additionalProperties": .bool(false)]
    }
}
