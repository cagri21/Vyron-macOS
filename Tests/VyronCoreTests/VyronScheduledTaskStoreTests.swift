import Foundation
import XCTest
@testable import VyronCore

final class VyronScheduledTaskStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronScheduledTasks-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func task() -> VyronScheduledTask {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let model = VyronScheduledModelSelection(
            connectionID: UUID(),
            model: "local-model",
            automaticallySelect: false,
            effort: .automatic
        )
        return VyronScheduledTask(
            id: UUID(),
            definition: VyronScheduledTaskDefinition(
                title: "Review the project",
                prompt: "Read the project notes and suggest the next step.",
                context: VyronScheduledTaskContext(workspacePath: "/tmp/Project", mode: .plan, model: model)
            ),
            schedule: VyronTaskSchedule(startsAt: start, recurrence: .daily, timeZoneIdentifier: "Europe/Istanbul"),
            progress: VyronScheduledTaskProgress(
                isEnabled: true,
                nextRunAt: start,
                lastRun: VyronScheduledTaskRun(
                    id: UUID(),
                    scheduledAt: start,
                    state: .completed,
                    output: VyronScheduledTaskRunOutput(
                        startedAt: start,
                        finishedAt: start.addingTimeInterval(30),
                        conversationID: UUID(),
                        detail: "Ready for review."
                    )
                )
            )
        )
    }

    func testMissingStoreIsEmptyAndRoundTripRetainsContextAndRun() throws {
        let directory = try temporaryDirectory().appendingPathComponent("Private", isDirectory: true)
        let store = VyronScheduledTaskStore(fileURL: directory.appendingPathComponent("scheduled-tasks.json"))
        XCTAssertEqual(try store.load(), [])
        let saved = [task()]
        try store.save(saved)
        XCTAssertEqual(try store.load(), saved)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        try store.save([])
        XCTAssertEqual(try store.load(), [])
    }

    func testCorruptOriginalCannotBeOverwritten() throws {
        let store = VyronScheduledTaskStore(fileURL: try temporaryDirectory().appendingPathComponent("tasks.json"))
        let original = Data("unreadable original".utf8)
        try original.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save([task()]))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
    }

    func testUnsupportedVersionCannotBeOverwritten() throws {
        let store = VyronScheduledTaskStore(fileURL: try temporaryDirectory().appendingPathComponent("tasks.json"))
        let original = Data(#"{"version":2,"tasks":[]}"#.utf8)
        try original.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load()) { error in
            guard case VyronScheduledTaskError.unsupportedVersion = error else {
                return XCTFail("Expected unsupported version, received \(error)")
            }
        }
        XCTAssertThrowsError(try store.save([]))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
    }

    func testDuplicateIdentityAndInvalidTaskDoNotReplaceSavedRecords() throws {
        let store = VyronScheduledTaskStore(fileURL: try temporaryDirectory().appendingPathComponent("tasks.json"))
        let saved = task()
        try store.save([saved])
        let original = try Data(contentsOf: store.fileURL)
        XCTAssertThrowsError(try store.save([saved, saved]))
        var invalid = task()
        invalid.definition.prompt = " \n "
        XCTAssertThrowsError(try store.save([invalid]))
        invalid = task()
        invalid.definition.context.workspacePath = "relative/path"
        XCTAssertThrowsError(try store.save([invalid]))
        invalid = task()
        invalid.progress.nextRunAt = invalid.schedule.startsAt.addingTimeInterval(-1)
        XCTAssertThrowsError(try store.save([invalid]))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
    }

    func testSymlinkStoreIsRejectedWithoutChangingTarget() throws {
        let directory = try temporaryDirectory()
        let target = directory.appendingPathComponent("target.json")
        let original = Data(#"{"version":1,"tasks":[]}"#.utf8)
        try original.write(to: target)
        let store = VyronScheduledTaskStore(fileURL: directory.appendingPathComponent("tasks.json"))
        try FileManager.default.createSymbolicLink(at: store.fileURL, withDestinationURL: target)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save([task()]))
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    func testPromptLimitsMatchExecutionModes() throws {
        var record = task()
        record.definition.prompt = String(repeating: "a", count: 3_001)
        XCTAssertThrowsError(try record.validated())
        record.definition.context.mode = .agent
        XCTAssertThrowsError(try record.validated())
        record.definition.context.mode = .chat
        XCTAssertNoThrow(try record.validated())
        record.definition.prompt = String(repeating: "a", count: 12_001)
        XCTAssertThrowsError(try record.validated())
        record.definition.prompt = String(repeating: "🎬", count: 3_001)
        XCTAssertThrowsError(try record.validated())
    }

    func testDevelopmentModesRequireProjectWhileChatCanBeUnbound() throws {
        var record = task()
        record.definition.context.workspacePath = nil
        XCTAssertThrowsError(try record.validated())
        record.definition.context.mode = .agent
        XCTAssertThrowsError(try record.validated())
        record.definition.context.mode = .chat
        XCTAssertNoThrow(try record.validated())
    }

    func testOversizedAndDuplicateArchivesAreRejected() throws {
        let store = VyronScheduledTaskStore(fileURL: try temporaryDirectory().appendingPathComponent("tasks.json"))
        let record = task()
        let duplicate = try JSONEncoder().encode(VyronScheduledTaskArchive(tasks: [record, record]))
        try duplicate.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        let oversized = Data(repeating: 32, count: VyronScheduledTaskLimits.storeBytes + 1)
        try oversized.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save([]))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), oversized)
    }
}
