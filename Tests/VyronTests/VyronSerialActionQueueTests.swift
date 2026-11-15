import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronSerialActionQueueTests: XCTestCase {
    func testActionsRunInSubmissionOrderAcrossSuspensionAndFailure() async throws {
        let queue = VyronSerialActionQueue()
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        var events: [String] = []

        let first = Task {
            try await queue.perform {
                events.append("first started")
                started.continuation.yield()
                for await _ in release.stream { break }
                events.append("first finished")
                throw URLError(.cannotOpenFile)
            }
        }
        for await _ in started.stream { break }

        let second = await submit {
            try await queue.perform { events.append("second") }
        }
        let third = await submit {
            try await queue.perform { events.append("third") }
        }
        XCTAssertEqual(events, ["first started"])

        release.continuation.finish()
        do {
            try await first.value
            XCTFail("Expected the first action to fail.")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cannotOpenFile)
        }
        try await second.value
        try await third.value
        XCTAssertEqual(events, ["first started", "first finished", "second", "third"])
    }

    func testCancellingWaitingActionSkipsItAndKeepsLaterActionsQueued() async throws {
        let queue = VyronSerialActionQueue()
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let cancellation = AsyncStream<Void>.makeStream()
        var events: [String] = []

        let first = Task {
            try await queue.perform {
                started.continuation.yield()
                for await _ in release.stream { break }
                events.append("first finished")
            }
        }
        for await _ in started.stream { break }

        let waiting = await submit {
            defer {
                cancellation.continuation.yield()
                cancellation.continuation.finish()
            }
            try await queue.perform { events.append("cancelled action ran") }
        }
        let next = await submit {
            try await queue.perform { events.append("next") }
        }
        waiting.cancel()

        let timeout = Task {
            try await Task.sleep(for: .seconds(1))
            cancellation.continuation.finish()
        }
        var cancelledWhileFirstWasActive = false
        for await _ in cancellation.stream {
            cancelledWhileFirstWasActive = true
            break
        }
        timeout.cancel()
        XCTAssertTrue(cancelledWhileFirstWasActive)
        XCTAssertTrue(events.isEmpty)

        release.continuation.finish()
        try await first.value
        do {
            try await waiting.value
            XCTFail("Expected the waiting action to be cancelled.")
        } catch is CancellationError {
            XCTAssertEqual(events.first, "first finished")
        }
        try await next.value
        XCTAssertEqual(events, ["first finished", "next"])
    }

    func testActiveActionSeesCallerCancellationAndReleasesTheQueue() async throws {
        let queue = VyronSerialActionQueue()
        let started = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        var activeSawCancellation = false

        let active = Task {
            try await queue.perform {
                started.continuation.yield()
                for await _ in release.stream { break }
                activeSawCancellation = Task.isCancelled
            }
        }
        for await _ in started.stream { break }
        let next = Task { try await queue.perform { "next" } }

        active.cancel()
        release.continuation.finish()
        do {
            try await active.value
            XCTFail("Expected the active action to report caller cancellation.")
        } catch is CancellationError {
            XCTAssertTrue(activeSawCancellation)
        }
        let result = try await next.value
        XCTAssertEqual(result, "next")
    }

    private func submit(_ operation: @escaping @MainActor () async throws -> Void) async -> Task<Void, Error> {
        let submitted = AsyncStream<Void>.makeStream()
        let task = Task {
            submitted.continuation.yield()
            try await operation()
        }
        for await _ in submitted.stream { break }
        return task
    }
}
