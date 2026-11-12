import Foundation
import XCTest
@testable import VyronCore
import VyronDevelopment

final class VyronDevelopmentFileOperationEvidenceTests: XCTestCase {
    func testLegacyCheckpointShapeDecodesAndReencodesWithoutNewKeys() throws {
        var original = task()
        try original.recordFile(file("Sources/App.swift", content: "original", at: 10))
        let encoded = try JSONEncoder().encode(original)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let progress = try XCTUnwrap(json["progress"] as? [String: Any])
        XCTAssertEqual(Set(progress.keys), ["files", "checks", "integrations", "context"])
        let restored = try JSONDecoder().decode(VyronDevelopmentTaskState.self, from: encoded)
        XCTAssertEqual(restored, original)
        XCTAssertTrue(restored.progress.fileOperations.isEmpty)
    }

    func testMoveRemapsOnlyItsSourceSubtreeAndRecordsNewLocationTime() throws {
        var state = task()
        try state.recordFile(file("Sources/App.swift", content: "app", at: 10))
        try state.recordFile(file("SourcesExtra/Keep.swift", content: "keep", at: 11))
        try state.recordFileOperation(operation(.move, source: "Sources", destination: "AppSources", at: 20))

        XCTAssertEqual(state.progress.files.map(\.path), ["AppSources/App.swift", "SourcesExtra/Keep.swift"])
        let moved = try XCTUnwrap(state.progress.files.first { $0.path == "AppSources/App.swift" })
        XCTAssertTrue(moved.matches(content: "app"))
        XCTAssertEqual(moved.recordedAt, date(20))
        XCTAssertEqual(moved.status, .saved)
        let encoded = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(VyronDevelopmentTaskState.self, from: encoded)
        try restored.validate(projectPath: state.identity.projectPath)
        XCTAssertEqual(restored, state)
    }

    func testPathsOnlyOperationEvidenceRetainsUnknownImpactOnDecoding() throws {
        let original = operation(.move, source: "Old", destination: "New", at: 20)
        let encoded = try JSONEncoder().encode(original)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let impact = try XCTUnwrap(legacy.removeValue(forKey: "impact") as? [String: Any])
        legacy["paths"] = impact["paths"]
        let restored = try JSONDecoder().decode(
            VyronDevelopmentFileOperationEvidence.self, from: JSONSerialization.data(withJSONObject: legacy)
        )
        try restored.validate()
        XCTAssertEqual(restored.paths, original.paths)
        XCTAssertFalse(restored.hasCompleteImpact)
        XCTAssertTrue(restored.affectedFilePaths.isEmpty)
    }

    func testRenamePreservesContentHashAndUnchangedStatus() throws {
        var state = task()
        try state.recordFile(VyronDevelopmentFileProgress(
            path: "Old.swift", contentHash: VyronDevelopmentFileProgress.hash(content: "same"),
            status: .unchanged, recordedAt: date(10)
        ))
        try state.recordFileOperation(operation(.rename, source: "Old.swift", destination: "New.swift", at: 20))
        XCTAssertEqual(state.progress.files.map(\.path), ["New.swift"])
        XCTAssertEqual(state.progress.files.first?.status, .unchanged)
        XCTAssertTrue(try XCTUnwrap(state.progress.files.first).matches(content: "same"))
    }

    func testCaseAliasesRemapOnlyOnCaseInsensitiveVolumes() throws {
        for isCaseSensitive in [false, true] {
            var before = task()
            try before.recordFile(file("sources/A.swift", content: "source", at: 10))
            var after = before
            try after.recordFileOperation(VyronDevelopmentFileOperationEvidence(
                id: UUID(), kind: .move,
                impact: .complete(VyronProjectFileOperationImpact(
                    paths: VyronProjectFileOperationPaths(sourcePath: "Sources", destinationPath: "Moved"),
                    affectedFilePaths: ["Sources/A.swift", "Moved/A.swift"], isCaseSensitive: isCaseSensitive
                )),
                recordedAt: date(20)
            ))
            let expected = isCaseSensitive ? "sources/A.swift" : "Moved/A.swift"
            XCTAssertEqual(after.progress.files.map(\.path), [expected])
            let merged = try VyronDevelopmentTaskState(continuing: before.identity, checkpoints: [before, after])
            XCTAssertEqual(merged.progress.files.map(\.path), [expected])
            XCTAssertTrue(try XCTUnwrap(merged.progress.files.first).matches(content: "source"))
        }
    }

    func testTrashCannotResurrectRemovedEvidenceDuringContinuationMerge() throws {
        var before = task()
        try before.recordFile(file("Unused/A.swift", content: "A", at: 10))
        try before.recordFile(file("Keep.swift", content: "keep", at: 10))
        var after = before
        try after.recordFileOperation(operation(.trash, source: "Unused", at: 20))
        let merged = try VyronDevelopmentTaskState(continuing: before.identity, checkpoints: [before, after, before])
        XCTAssertEqual(merged.progress.files.map(\.path), ["Keep.swift"])
        XCTAssertEqual(merged.progress.fileOperations, after.progress.fileOperations)
    }

    func testLaterSourceRecreationIsRetainedAfterTrash() throws {
        var before = task()
        try before.recordFile(file("A.swift", content: "old", at: 10))
        var after = before
        try after.recordFileOperation(operation(.trash, source: "A.swift", at: 20))
        try after.recordFile(file("A.swift", content: "new", at: 30))
        let merged = try VyronDevelopmentTaskState(continuing: before.identity, checkpoints: [before, after])
        XCTAssertEqual(merged.progress.files.map(\.path), ["A.swift"])
        XCTAssertTrue(try XCTUnwrap(merged.progress.files.first).matches(content: "new"))
    }

    func testSwappingTrackedFilesRetainsBothIdentitiesAndDoesNotReplayOldMappings() throws {
        var before = task()
        try before.recordFile(file("A.swift", content: "original A", at: 10))
        try before.recordFile(file("B.swift", content: "original B", at: 10))
        var after = before
        try after.recordFileOperation(operation(.move, source: "A.swift", destination: "Temporary.swift", at: 20))
        try after.recordFileOperation(operation(.move, source: "B.swift", destination: "A.swift", at: 30))
        try after.recordFileOperation(operation(.move, source: "Temporary.swift", destination: "B.swift", at: 40))
        try assertSwap(after)

        let merged = try VyronDevelopmentTaskState(continuing: before.identity, checkpoints: [before, after])
        try assertSwap(merged)
        XCTAssertEqual(merged.progress.fileOperations.count, 3)
        let remerged = try VyronDevelopmentTaskState(continuing: before.identity, checkpoints: [before, merged, after])
        try assertSwap(remerged)
    }

    func testMoveThenTrashDoesNotRestoreOldOrIntermediatePaths() throws {
        var before = task()
        try before.recordFile(file("Old/A.swift", content: "A", at: 10))
        var after = before
        try after.recordFileOperation(operation(.move, source: "Old", destination: "New", at: 20))
        try after.recordFileOperation(operation(.trash, source: "New", at: 30))
        let merged = try VyronDevelopmentTaskState(continuing: before.identity, checkpoints: [before, after])
        XCTAssertTrue(merged.progress.files.isEmpty)
        XCTAssertEqual(merged.progress.fileOperations.count, 2)
    }

    func testConflictingOperationIdentityDoesNotChangeState() throws {
        var state = task()
        let first = operation(.move, source: "A", destination: "B", at: 20)
        try state.recordFileOperation(first)
        let original = state
        let conflict = VyronDevelopmentFileOperationEvidence(
            id: first.id, kind: .trash,
            impact: .legacy(VyronProjectFileOperationPaths(sourcePath: "Other", destinationPath: nil)),
            recordedAt: date(30)
        )
        XCTAssertThrowsError(try state.recordFileOperation(conflict))
        XCTAssertEqual(state, original)
    }

    func testAmbiguousExecutionTimesAndMalformedPathsAreRejectedWithoutMutation() throws {
        var state = task()
        try state.recordFileOperation(operation(.move, source: "A", destination: "B", at: 20))
        let original = state
        XCTAssertThrowsError(try state.recordFileOperation(operation(.trash, source: "B", at: 20)))
        XCTAssertEqual(state, original)
        for source in ["/absolute", "../outside", ".", "", "A//B"] {
            XCTAssertThrowsError(try state.recordFileOperation(operation(.trash, source: source, at: 30)))
            XCTAssertEqual(state, original)
        }
    }

    private func assertSwap(_ state: VyronDevelopmentTaskState) throws {
        XCTAssertEqual(Set(state.progress.files.map(\.path)), ["A.swift", "B.swift"])
        XCTAssertTrue(try XCTUnwrap(state.progress.files.first { $0.path == "A.swift" }).matches(content: "original B"))
        XCTAssertTrue(try XCTUnwrap(state.progress.files.first { $0.path == "B.swift" }).matches(content: "original A"))
    }

    private func task() -> VyronDevelopmentTaskState {
        VyronDevelopmentTaskState(identity: VyronDevelopmentTaskIdentity(
            projectPath: "/Projects/Fixture", originalGoal: "Organize project files."
        ))
    }

    private func file(_ path: String, content: String, at seconds: TimeInterval) -> VyronDevelopmentFileProgress {
        VyronDevelopmentFileProgress(
            path: path, contentHash: VyronDevelopmentFileProgress.hash(content: content), recordedAt: date(seconds)
        )
    }

    private func operation(
        _ kind: VyronProjectFileOperationKind,
        source: String,
        destination: String? = nil,
        at seconds: TimeInterval
    ) -> VyronDevelopmentFileOperationEvidence {
        VyronDevelopmentFileOperationEvidence(
            id: UUID(), kind: kind,
            impact: .complete(VyronProjectFileOperationImpact(
                paths: VyronProjectFileOperationPaths(sourcePath: source, destinationPath: destination),
                affectedFilePaths: [source] + (destination.map { [$0] } ?? [])
            )),
            recordedAt: date(seconds)
        )
    }

    private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
}
