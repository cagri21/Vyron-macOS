import Darwin
import Foundation
import UniformTypeIdentifiers
import VyronModelDomain

actor VyronDocumentAttachmentLoader {
    static let contentTypes = VyronDocumentAttachmentFormat.contentTypes

    static func supports(filename: String) -> Bool {
        VyronDocumentAttachmentFormat.supports(filename: filename)
    }

    static func prefersType(_ type: UTType) -> Bool {
        VyronDocumentAttachmentFormat.prefersType(type)
    }

    func load(_ url: URL) throws -> VyronFileAttachment {
        try Task.checkCancellation()
        guard url.isFileURL else { throw VyronDocumentAttachmentError.unreadable }
        let filename = url.lastPathComponent
        guard Self.supports(filename: filename) else { throw VyronDocumentAttachmentError.unsupported }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw VyronDocumentAttachmentError.unreadable }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG
        else { throw VyronDocumentAttachmentError.unreadable }
        let limit = VyronDocumentAttachmentLimits.maximumImportBytes
        guard metadata.st_size <= limit else { throw VyronDocumentAttachmentError.tooLarge }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data: Data
        do {
            data = try file.read(upToCount: limit + 1) ?? Data()
        } catch {
            throw VyronDocumentAttachmentError.unreadable
        }
        return try load(data, name: filename)
    }

    func load(_ data: Data, name: String) throws -> VyronFileAttachment {
        try Task.checkCancellation()
        guard Self.supports(filename: name) else { throw VyronDocumentAttachmentError.unsupported }
        guard data.count <= VyronDocumentAttachmentLimits.maximumImportBytes
        else { throw VyronDocumentAttachmentError.tooLarge }
        guard let text = Self.decode(data),
            !text.unicodeScalars.contains(where: { scalar in
                scalar.properties.generalCategory == .control && !CharacterSet.whitespacesAndNewlines.contains(scalar)
            })
        else { throw VyronDocumentAttachmentError.unreadable }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw VyronDocumentAttachmentError.noText }
        let excerpt = boundedAgentPrefix(text, bytes: VyronDocumentAttachmentLimits.maximumTextBytes)
        try Task.checkCancellation()
        return VyronFileAttachment(
            info: .init(name: name, kind: .document),
            text: excerpt,
            isTruncated: excerpt.utf8.count < text.utf8.count
        )
    }

    private static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) { return String(data: data.dropFirst(2), encoding: .utf16LittleEndian) }
        if data.starts(with: [0xFE, 0xFF]) { return String(data: data.dropFirst(2), encoding: .utf16BigEndian) }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
        return String(data: data, encoding: .utf8)
    }
}
