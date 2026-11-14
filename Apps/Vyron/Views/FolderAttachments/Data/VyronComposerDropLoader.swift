import AppKit
import UniformTypeIdentifiers
import VyronCore

@MainActor
final class VyronComposerDropLoader {
    static var contentTypes: [String] {
        let identifiers = VyronScreenshotDropLoader.contentTypes + VyronComposerFileLoader.fileTypes.map(\.identifier)
        return Array(Set(identifiers)).sorted()
    }

    private let providers: [NSItemProvider]

    init(providers: [NSItemProvider]) {
        self.providers = providers
    }

    static func accepts(_ providers: [NSItemProvider]) -> Bool {
        !providers.isEmpty && providers.count <= VyronImageAttachment.maximumCount + AppModel.maximumFolderAttachments
            + VyronPDFAttachmentLimits.maximumCount + VyronFileAttachmentLimits.maximumCount
            + AppModel.maximumApplicationAttachments
            && providers.allSatisfy {
                hasFileURL($0) || hasPDF($0) || audioType($0) != nil || documentType($0) != nil
                    || VyronScreenshotDropLoader.hasImageRepresentation($0)
            }
    }

    func load() async throws -> VyronComposerAttachments {
        guard Self.accepts(providers) else { throw VyronFolderAttachmentError.invalidFolder }
        var result = VyronComposerAttachments()
        let loader = VyronComposerFileLoader()
        for provider in providers {
            try Task.checkCancellation()
            let filename = provider.suggestedName
            let audioType = Self.audioType(provider)
            let documentType = Self.documentType(provider)
            let hasPixels = VyronScreenshotDropLoader.hasImageRepresentation(provider)
            let hasPDF = Self.hasPDF(provider)
            let suffix = filename.map { ($0 as NSString).pathExtension.lowercased() }
            let hasDocumentName = filename.map(VyronDocumentAttachmentLoader.supports(filename:)) == true
            let hasAudioName = filename.map(VyronAudioAttachmentLoader.supports(filename:)) == true
            let isApplication = suffix == "app"
                || provider.hasItemConformingToTypeIdentifier(UTType.applicationBundle.identifier)
            if Self.hasFileURL(provider), hasPDF || audioType != nil || hasDocumentName || hasAudioName
                || suffix == "pdf" || isApplication || !hasPixels {
                let data = try await Self.read(provider, typeIdentifier: UTType.fileURL.identifier)
                guard let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL
                else { throw VyronFolderAttachmentError.invalidFolder }
                try await loader.append(url, to: &result)
            } else if hasPDF {
                let data = try await Self.read(provider, typeIdentifier: UTType.pdf.identifier)
                try await loader.appendPDF(
                    data, name: filename ?? VyronFolderAttachmentText.pdfDroppedName, to: &result
                )
            } else if let audioType {
                let data = try await Self.read(provider, typeIdentifier: audioType)
                let name = Self.audioFilename(filename, typeIdentifier: audioType)
                try await loader.appendAudio(data, name: name, to: &result)
            } else if hasPixels {
                guard result.images.count < VyronImageAttachment.maximumCount
                else { throw VyronScreenshotImportError.tooLarge }
                result.images += try await VyronScreenshotDropLoader(providers: [provider]).load()
            } else if let documentType, let filename {
                let data = try await Self.read(provider, typeIdentifier: documentType)
                try await loader.appendDocument(data, name: filename, to: &result)
            }
        }
        return result
    }

    private static func hasFileURL(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
    }

    private static func hasPDF(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
    }

    private static func audioType(_ provider: NSItemProvider) -> String? {
        let accepted = VyronAudioAttachmentLoader.acceptedTypes.map(\.identifier)
        return provider.registeredTypeIdentifiers.first {
            accepted.contains($0) || UTType($0)?.conforms(to: .audio) == true
        }
    }

    private static func documentType(_ provider: NSItemProvider) -> String? {
        // A text representation without a filename is a dragged text selection.
        guard let filename = provider.suggestedName, VyronDocumentAttachmentLoader.supports(filename: filename)
        else { return nil }
        let accepted = VyronDocumentAttachmentLoader.contentTypes.map(\.identifier)
        return provider.registeredTypeIdentifiers.first {
            accepted.contains($0) || UTType($0).map(VyronDocumentAttachmentLoader.prefersType) == true
        }
    }

    private static func audioFilename(_ filename: String?, typeIdentifier: String) -> String {
        let name = filename ?? VyronFolderAttachmentText.fileDroppedName
        guard (name as NSString).pathExtension.isEmpty,
            let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension else { return name }
        return name + "." + fileExtension
    }

    private static func read(_ provider: NSItemProvider, typeIdentifier: String) async throws -> Data {
        try await VyronScreenshotDropRead(provider: provider, typeIdentifier: typeIdentifier).load()
    }
}
