import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronForegroundRunTests: XCTestCase {
    func testStoppedRequestDoesNotOwnReplacementButRemainsAvailableToShutdown() async {
        let run = VyronForegroundRun()
        let first = VyronResponseIdentity(generationID: UUID(), conversationID: UUID(), messageID: UUID())
        let next = VyronResponseIdentity(generationID: UUID(), conversationID: first.conversationID, messageID: UUID())
        let started = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        var finished = false

        run.begin(first)
        run.start(first) {
            await withCheckedContinuation { continuation in
                release = continuation
                started.continuation.yield()
                started.continuation.finish()
            }
            finished = true
        }
        for await _ in started.stream { break }

        run.stop()
        run.begin(next)
        run.complete(first.generationID)
        XCTAssertFalse(run.owns(first))
        XCTAssertTrue(run.owns(next))

        let pending = run.shutdown()
        XCTAssertEqual(pending.count, 1)
        XCTAssertFalse(run.owns(next))
        release?.resume()
        for task in pending { await task.value }
        XCTAssertTrue(finished)
    }
}
