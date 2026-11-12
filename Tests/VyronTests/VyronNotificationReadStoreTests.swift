import Foundation
import XCTest
@testable import Vyron

final class VyronNotificationReadStoreTests: XCTestCase {
    func testMissingStoreDoesNotCreateFilesAndExplicitReadsPersistPrivately() throws {
        let directory = try directory()
        let privateDirectory = directory.appendingPathComponent("Private", isDirectory: true)
        let file = privateDirectory.appendingPathComponent("notification-read.json")
        let store = VyronNotificationReadStore(fileURL: file)
        XCTAssertNil(try store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: privateDirectory.path))
        let completed = id()
        let failed = id(kind: .failed)
        var state = VyronNotificationReadState.empty
        XCTAssertFalse(state.isRead(completed))
        try state.markRead(completed)
        try state.markAllRead(ids: [completed, failed])
        try store.save(state)
        let reopened = try XCTUnwrap(store.load())
        XCTAssertEqual(reopened, state)
        XCTAssertTrue(reopened.isRead(completed))
        XCTAssertTrue(reopened.isRead(failed))
        XCTAssertFalse(reopened.isRead(id()))
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: privateDirectory.path)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(state), try encoder.encode(reopened))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual(Set(json.keys), ["version", "readIDs"])
    }

    func testCapacityFailurePreservesAllPreviouslyReadIDsWithoutEviction() throws {
        let file = try directory().appendingPathComponent("notification-read.json")
        let store = VyronNotificationReadStore(fileURL: file)
        let ids = (0..<VyronNotificationLimits.maximumReadMarkers).map { _ in id() }
        var state = VyronNotificationReadState()
        try state.markAllRead(ids: ids)
        try store.save(state)
        let saved = try Data(contentsOf: store.fileURL)
        let previous = state
        XCTAssertThrowsError(try state.markRead(id()))
        XCTAssertEqual(state, previous)
        XCTAssertTrue(ids.allSatisfy(state.isRead))
        let reopened = try XCTUnwrap(store.load())
        XCTAssertTrue(ids.allSatisfy(reopened.isRead))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), saved)
        try state.markRead(ids[0])
        XCTAssertEqual(state, previous)
    }

    func testCorruptionAndUnsupportedVersionDisableReplacementAndPreserveOriginalBytes() throws {
        let directory = try directory()
        let file = directory.appendingPathComponent("notification-read.json")
        let store = VyronNotificationReadStore(fileURL: file)
        for bytes in [
            Data("not JSON".utf8),
            Data("{\"version\":2,\"readIDs\":[]}".utf8),
            Data(repeating: 0x20, count: VyronNotificationLimits.maximumStoredBytes + 1)
        ] {
            try bytes.write(to: file)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save(.empty))
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    func testDuplicateReadIDsAreRejectedInsteadOfSilentlyAcceptingDamagedHistory() throws {
        let file = try directory().appendingPathComponent("notification-read.json")
        let marker = id()
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(marker)) as? [String: Any])
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "readIDs": [encoded, encoded]])
        try data.write(to: file)
        let store = VyronNotificationReadStore(fileURL: file)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(.empty))
        XCTAssertEqual(try Data(contentsOf: file), data)
    }

    func testFileAndPrivateDirectorySymlinksCannotRedirectReadsOrWrites() throws {
        let directory = try directory()
        let external = directory.appendingPathComponent("OtherStorage", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let externalFile = external.appendingPathComponent("notification-read.json")
        var state = VyronNotificationReadState()
        try state.markRead(id())
        try VyronNotificationReadStore(fileURL: externalFile).save(state)
        let original = try Data(contentsOf: externalFile)
        let fileLink = directory.appendingPathComponent("notification-read.json")
        try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: externalFile)
        let linkedFileStore = VyronNotificationReadStore(fileURL: fileLink)
        XCTAssertThrowsError(try linkedFileStore.load())
        XCTAssertThrowsError(try linkedFileStore.save(.empty))
        let directoryLink = directory.appendingPathComponent("Private")
        try FileManager.default.createSymbolicLink(at: directoryLink, withDestinationURL: external)
        let linkedDirectoryStore = VyronNotificationReadStore(
            fileURL: directoryLink.appendingPathComponent("notification-read.json")
        )
        XCTAssertThrowsError(try linkedDirectoryStore.load())
        XCTAssertThrowsError(try linkedDirectoryStore.save(.empty))
        XCTAssertEqual(try Data(contentsOf: externalFile), original)
    }

    func testExternalCorruptionAfterSuccessfulLoadDoesNotGetOverwrittenByNextReadAction() throws {
        let file = try directory().appendingPathComponent("notification-read.json")
        let store = VyronNotificationReadStore(fileURL: file)
        var original = VyronNotificationReadState()
        try original.markRead(id())
        try store.save(original)
        var pending = try XCTUnwrap(store.load())
        try pending.markRead(id(kind: .failed))
        let corruption = Data("External damaged state".utf8)
        try corruption.write(to: file)
        XCTAssertThrowsError(try store.save(pending))
        XCTAssertEqual(try Data(contentsOf: file), corruption)
        XCTAssertNotEqual(pending, original)
    }

    func testIntermediateSymlinkAncestorRejectsExistingAndMissingChildWithoutRedirectedWrites() throws {
        for missingChild in [false, true] {
            let directory = try directory()
            let external = directory.appendingPathComponent("External", isDirectory: true)
            try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
            let externalChild = external.appendingPathComponent("Nested/Private", isDirectory: true)
            let externalFile = externalChild.appendingPathComponent("notification-read.json")
            var original = Data()
            if !missingChild {
                var state = VyronNotificationReadState()
                try state.markRead(id())
                try VyronNotificationReadStore(fileURL: externalFile).save(state)
                original = try Data(contentsOf: externalFile)
            }
            let linkedAncestor = directory.appendingPathComponent("LinkedAncestor")
            try FileManager.default.createSymbolicLink(at: linkedAncestor, withDestinationURL: external)
            let redirected = linkedAncestor.appendingPathComponent("Nested/Private/notification-read.json")
            let store = VyronNotificationReadStore(fileURL: redirected)

            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save(.empty))
            if missingChild {
                XCTAssertFalse(FileManager.default.fileExists(atPath: externalChild.path))
            } else {
                XCTAssertEqual(try Data(contentsOf: externalFile), original)
            }
        }
    }

    func testMixedTargetReadMarkersRoundTripWithoutCrossTargetOrFutureKindReads() throws {
        let file = try directory().appendingPathComponent("notification-read.json")
        let store = VyronNotificationReadStore(fileURL: file)
        let response = VyronNotificationResponseID(conversationID: UUID(), responseID: UUID())
        let working = VyronNotificationID(target: .response(response), kind: .working)
        let completion = VyronNotificationID(target: .response(response), kind: .completed)
        let scheduled = VyronNotificationID(
            target: .scheduledRun(VyronNotificationScheduledRunID(taskID: UUID(), runID: UUID())), kind: .failed
        )
        let plugins = VyronNotificationID(
            target: .plugins, kind: .attention(VyronNotificationAttentionID(requestID: UUID()))
        )
        var state = VyronNotificationReadState()
        try state.markAllRead(ids: [working, scheduled, plugins])
        try store.save(state)
        let reopened = try XCTUnwrap(store.load())
        XCTAssertTrue(reopened.isRead(working))
        XCTAssertTrue(reopened.isRead(scheduled))
        XCTAssertTrue(reopened.isRead(plugins))
        XCTAssertFalse(reopened.isRead(completion))
    }

    private func id(kind: VyronNotificationKind = .completed) -> VyronNotificationID {
        VyronNotificationID(
            target: .response(VyronNotificationResponseID(conversationID: UUID(), responseID: UUID())), kind: kind
        )
    }

    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("VyronNotificationRead-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }
}
