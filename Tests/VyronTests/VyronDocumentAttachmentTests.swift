import Foundation
import XCTest
import VyronModelDomain
@testable import Vyron

@MainActor
final class VyronDocumentAttachmentTests: XCTestCase {
    func testLoadsMixedCaseCSVFromFileAndPreservesRows() async throws {
        let directory = try temporaryDirectory()
        defer { removeDirectory(directory) }
        let file = directory.appendingPathComponent("Quarterly.CSV")
        let content = "team,total\nİstanbul,20\n👩‍💻,15\n"
        try Data(content.utf8).write(to: file)

        let attachment = try await VyronDocumentAttachmentLoader().load(file)
        XCTAssertEqual(attachment.info.name, "Quarterly.CSV")
        XCTAssertEqual(attachment.info.kind, .document)
        XCTAssertEqual(attachment.text, content)
        XCTAssertFalse(attachment.isTruncated)
    }

    func testUTF16TruncatesOnAValidUTF8Boundary() async throws {
        let prefix = String(repeating: "a", count: VyronDocumentAttachmentLimits.maximumTextBytes - 1)
        let encoded = try XCTUnwrap((prefix + "élast section").data(using: .utf16LittleEndian))
        var data = Data([0xFF, 0xFE])
        data.append(encoded)

        let attachment = try await VyronDocumentAttachmentLoader().load(data, name: "notes.md")
        XCTAssertEqual(attachment.text, prefix)
        XCTAssertTrue(attachment.isTruncated)
    }

    func testRejectsBinaryTextAndUnsupportedFormats() async throws {
        let loader = VyronDocumentAttachmentLoader()
        let binary = Data([0x41, 0x00, 0x42])
        do {
            _ = try await loader.load(binary, name: "fake.txt")
            XCTFail("Binary input must be rejected.")
        } catch let error as VyronDocumentAttachmentError {
            XCTAssertEqual(error, .unreadable)
        }
        do {
            _ = try await loader.load(Data("Some content".utf8), name: "file.docx")
            XCTFail("An unsupported type must be rejected.")
        } catch let error as VyronDocumentAttachmentError {
            XCTAssertEqual(error, .unsupported)
        }
    }

    func testRefusesAFileSymlinkAndOversizedDocument() async throws {
        let directory = try temporaryDirectory()
        defer { removeDirectory(directory) }
        let original = directory.appendingPathComponent("content.txt")
        try Data("Hello".utf8).write(to: original)
        let link = directory.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)

        let loader = VyronDocumentAttachmentLoader()
        do {
            _ = try await loader.load(link)
            XCTFail("A symbolic link must not be read.")
        } catch let error as VyronDocumentAttachmentError {
            XCTAssertEqual(error, .unreadable)
        }
        do {
            let oversized = Data(repeating: 97, count: VyronDocumentAttachmentLimits.maximumImportBytes + 1)
            _ = try await loader.load(oversized, name: "oversized.txt")
            XCTFail("An oversized document must not be read.")
        } catch let error as VyronDocumentAttachmentError {
            XCTAssertEqual(error, .tooLarge)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func removeDirectory(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            XCTFail("Could not remove document attachment fixture: \(error)")
        }
    }
}
