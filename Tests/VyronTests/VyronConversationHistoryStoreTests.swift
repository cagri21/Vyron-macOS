import Foundation
import XCTest
@testable import Vyron

final class VyronConversationHistoryStoreTests: XCTestCase {
    func testSavesPrivateHistoryAtTheExistingPathAndLoadsNewestFirst() throws {
        let store = makeStore()
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertEqual(try permissions(for: store.directory), 0o700)

        var older = Conversation(title: "Older", workspacePath: nil)
        older.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        var newer = Conversation(title: "Newer", workspacePath: nil)
        newer.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        try store.save([older, newer])

        let history = store.directory.appendingPathComponent("conversations.json")
        XCTAssertEqual(try permissions(for: history), 0o600)
        let stored = try JSONDecoder().decode([Conversation].self, from: Data(contentsOf: history))
        XCTAssertEqual(stored.map(\.id), [older.id, newer.id])
        XCTAssertEqual(try store.load().map(\.id), [newer.id, older.id])
    }

    func testPreservesUnreadableHistoryBytesInAPrivateRecoveryCopy() throws {
        let store = makeStore()
        XCTAssertFalse(try store.createRecoveryCopyIfPresent())
        _ = try store.load()

        let history = store.directory.appendingPathComponent("conversations.json")
        let unreadableHistory = Data("Incomplete history".utf8)
        try unreadableHistory.write(to: history)
        XCTAssertThrowsError(try store.load())
        XCTAssertTrue(try store.createRecoveryCopyIfPresent())

        let contents = try FileManager.default.contentsOfDirectory(
            at: store.directory,
            includingPropertiesForKeys: nil
        )
        let backups = contents.filter { $0.lastPathComponent.hasPrefix("conversations-recovery-") }
        XCTAssertEqual(backups.count, 1)
        let backup = try XCTUnwrap(backups.first)
        XCTAssertEqual(backup.pathExtension, "json")
        XCTAssertEqual(try Data(contentsOf: backup), unreadableHistory)
        XCTAssertEqual(try Data(contentsOf: history), unreadableHistory)
        XCTAssertEqual(try permissions(for: backup), 0o600)
    }

    private func makeStore() -> VyronConversationHistoryStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VyronHistoryTests-\(UUID())")
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        return VyronConversationHistoryStore(
            historyURL: VyronAppStoragePaths(directory: directory).url(for: .conversationHistory)
        )
    }

    private func permissions(for url: URL) throws -> Int? {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue
    }
}
