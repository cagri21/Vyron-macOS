import Foundation
import VyronDevelopment

struct VyronOfficeToolRequest: Sendable {
    let operation: VyronOfficeOperation
    let inputPath: String
    let outputPath: String
    let pages: [Int]

    init(call: DevelopmentToolCall) throws {
        let values = call.function.arguments
        let operation: VyronOfficeOperation
        switch call.function.name {
        case "office_convert": operation = .convert
        case "office_render": operation = .render
        case "office_recalculate": operation = .recalculate
        default: throw Self.invalid()
        }
        let keys: Set<String> = operation == .render
            ? ["input_path", "output_path", "pages"] : ["input_path", "output_path"]
        guard Set(values.keys).isSubset(of: keys),
            case .string(let inputPath) = values["input_path"],
            case .string(let outputPath) = values["output_path"],
            !inputPath.isEmpty, !outputPath.isEmpty
        else { throw Self.invalid() }
        let inputExtension = URL(fileURLWithPath: inputPath).pathExtension.lowercased()
        let officeExtensions: Set<String> = ["docx", "doc", "pptx", "ppt", "xlsx", "xls", "odt", "ods", "odp", "rtf"]
        switch operation {
        case .convert:
            guard officeExtensions.contains(inputExtension), outputPath.lowercased().hasSuffix(".pdf") else {
                throw Self.invalid()
            }
        case .recalculate:
            guard inputExtension == "xlsx", outputPath.lowercased().hasSuffix(".xlsx") else { throw Self.invalid() }
        case .render:
            guard officeExtensions.contains(inputExtension) || inputExtension == "pdf" else { throw Self.invalid() }
        case .status: throw Self.invalid()
        }
        var pages: [Int] = []
        if let pageValue = values["pages"] {
            guard case .array(let values) = pageValue, !values.isEmpty,
                values.count <= VyronOfficeLimits.maximumPages else { throw Self.invalid() }
            pages = try values.map { value in
                guard case .number(let number) = value, number.isFinite, number.rounded() == number,
                    number >= 1, number <= 10_000 else { throw Self.invalid() }
                return Int(number)
            }
            guard Set(pages).count == pages.count else { throw Self.invalid() }
        }
        self.operation = operation
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.pages = pages
    }

    private static func invalid() -> VyronOfficeError {
        VyronOfficeError(message: "Use supported Office input and new output paths. Conversion outputs PDF; "
            + "recalculation reads and writes XLSX; rendering creates a new PNG folder. "
            + "Pages must be distinct positive integers, at most 20.")
    }
}
