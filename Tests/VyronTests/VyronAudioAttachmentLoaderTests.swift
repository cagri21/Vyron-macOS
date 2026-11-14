import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronAudioAttachmentLoaderTests: XCTestCase {
    func testLoadsMP3WithoutTranscription() async throws {
        let loader = VyronAudioAttachmentLoader { _ in nil }
        let attachment = try await loader.load(VyronAudioAttachmentTestFixture.mp3(), name: "Sample.mp3")
        XCTAssertEqual(attachment.info.name, "Sample.mp3")
        XCTAssertEqual(attachment.info.kind, .audio)
        XCTAssertGreaterThan(try XCTUnwrap(attachment.info.duration), 0)
        XCTAssertNil(attachment.text)
        XCTAssertFalse(attachment.isTruncated)
    }

    func testValidAudioYieldsBoundedUnicodeTranscriptAndRemovesTemporaryFile() async throws {
        let (staged, continuation) = AsyncStream<URL>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let original = String(repeating: "Merhaba 👋 ", count: 1_000)
        let loader = VyronAudioAttachmentLoader { url in
            continuation.yield(url)
            continuation.finish()
            return original
        }
        let attachment = try await loader.load(VyronAudioAttachmentTestFixture.mp3(), name: "Long speech.mp3")
        let excerpt = try XCTUnwrap(attachment.text)
        let limit = VyronAudioAttachmentLimits.maximumTranscriptBytes
        XCTAssertTrue((limit - 3...limit).contains(excerpt.utf8.count))
        XCTAssertFalse(excerpt.contains("�"))
        XCTAssertTrue(attachment.isTruncated)
        var iterator = staged.makeAsyncIterator()
        let received = await iterator.next()
        let temporary = try XCTUnwrap(received)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
    }

    func testRejectsInvalidFileNamedMP3() async throws {
        let loader = VyronAudioAttachmentLoader { _ in nil }
        do {
            _ = try await loader.load(Data("This is not an audio file.".utf8), name: "invalid.mp3")
            XCTFail("Expected invalid audio to be rejected")
        } catch let error as VyronAudioAttachmentError {
            guard case .unreadable = error else { return XCTFail(error.localizedDescription) }
        }
    }
}
