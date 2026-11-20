import Foundation
import XCTest
@testable import Vyron
import VyronCore

@MainActor
final class VyronLargeCodebaseAnalysisFixture {
    static let sourceCount = 600
    static let earlyPath = "Sources/Feature000.swift"
    static let latePath = "Sources/Feature599.swift"
    static let earlyEvidence = "AUDIT_ME_EARLY_RETRY_WITHOUT_CANCELLATION"
    static let lateEvidence = "AUDIT_ME_LATE_UNBOUNDED_HISTORY"
    static let excludedEvidence = "EXCLUDED_FIXTURE_CANARY_NOT_A_REAL_CREDENTIAL"
    static let goalMarkers = ["REQUIREMENT_BEGIN", "REQUIREMENT_MIDDLE", "REQUIREMENT_END"]

    let test: VyronFeatureTestHarness
    let provider = VyronLargeCodebaseAnalysisProvider()
    private(set) var sourceContents: [String: Data] = [:]

    init(sourceCount: Int = VyronLargeCodebaseAnalysisFixture.sourceCount) throws {
        test = try VyronFeatureTestHarness()
        let sources = test.project.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        for index in 0..<sourceCount {
            let path = "Sources/Feature" + String(format: "%03d", index) + ".swift"
            let data = Data(Self.source(index: index).utf8)
            try data.write(to: test.project.appendingPathComponent(path))
            sourceContents[path] = data
        }
        try Data(Self.excludedEvidence.utf8).write(to: test.project.appendingPathComponent(".env"))
    }

    func prepare(mode: ComposerMode = .plan) async {
        test.model.modelSelection.isConnected = false
        test.model.modelSelection.activeConnectionID = nil
        test.model.modelSelection.connectionProfiles = []
        test.model.modelSelection.configuredInferenceClient = provider
        test.model.modelSelection.models = [
            LocalModel(name: "qwen3-coder:30b", size: 18_000_000_000, capabilities: ["tools"])
        ]
        test.model.modelSelection.selectedModel = "qwen3-coder:30b"
        test.model.modelSelection.automaticModelSelection = false
        test.model.modelSelection.isConnected = true
        test.model.computerWork.automaticRequestRouting = false
        test.model.skillContextLoader = { _ in .empty }
        await test.model.loadWorkspace(test.project)
        test.model.composer.mode = mode
    }

    func assertSourceUnchanged(file: StaticString = #filePath, line: UInt = #line) throws {
        let sources = test.project.appendingPathComponent("Sources", isDirectory: true)
        let entries = try XCTUnwrap(
            FileManager.default.enumerator(at: sources, includingPropertiesForKeys: [.isRegularFileKey]),
            file: file,
            line: line
        )
        var currentPaths: Set<String> = []
        for case let url as URL in entries {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                currentPaths.insert(String(url.path.dropFirst(test.project.path.count + 1)))
            }
        }
        XCTAssertEqual(currentPaths, Set(sourceContents.keys), file: file, line: line)
        for (path, contents) in sourceContents {
            XCTAssertEqual(
                try Data(contentsOf: test.project.appendingPathComponent(path)), contents, file: file, line: line
            )
        }
        XCTAssertTrue(test.model.inspector.developmentChanges.isEmpty, file: file, line: line)
        XCTAssertFalse(
            test.model.inspector.developmentEvents.contains { $0.kind == .commandStarted }, file: file, line: line
        )
        XCTAssertEqual(
            try Data(contentsOf: test.project.appendingPathComponent(".env")),
            Data(Self.excludedEvidence.utf8),
            file: file,
            line: line
        )
    }

    func plantEvidenceOutsideInitialSearchWindow() async throws -> String {
        let workspace = try XCTUnwrap(test.model.workspaceState.developmentWorkspace)
        let initial = try await workspace.listFiles(limit: 150)
        let included = Set(initial.map(\.path))
        let path = try XCTUnwrap(sourceContents.keys.sorted().first { !included.contains($0) })
        var contents = try XCTUnwrap(sourceContents[path])
        contents.append(Data("// DISCOVERY_BEYOND_INITIAL_WINDOW\n".utf8))
        try contents.write(to: test.project.appendingPathComponent(path))
        sourceContents[path] = contents
        let repeated = try await workspace.listFiles(limit: 150)
        XCTAssertFalse(repeated.contains { $0.path == path })
        return path
    }

    func plantEvidenceAfterSearchByteWindow() async throws -> String {
        let path = try await includedSourcePath()
        var contents = try XCTUnwrap(sourceContents[path])
        contents.append(Data(String(repeating: "// audit padding\n", count: 3_000).utf8))
        XCTAssertGreaterThan(contents.count, 40_000)
        contents.append(Data("// DISCOVERY_AFTER_FIRST_40KB\n".utf8))
        try contents.write(to: test.project.appendingPathComponent(path))
        sourceContents[path] = contents
        return path
    }

    func plantEvidenceBeforeSplitUTF8Scalar() async throws -> String {
        let path = try await includedSourcePath()
        var contents = Data("// DISCOVERY_BEFORE_SPLIT_UTF8\n// ".utf8)
        contents.append(Data(repeating: 0x20, count: 39_999 - contents.count))
        contents.append(Data("🙂\n".utf8))
        contents.append(try XCTUnwrap(sourceContents[path]))
        try contents.write(to: test.project.appendingPathComponent(path))
        sourceContents[path] = contents
        return path
    }

    func cleanUp() { test.cleanUp() }

    private func includedSourcePath() async throws -> String {
        let workspace = try XCTUnwrap(test.model.workspaceState.developmentWorkspace)
        let initial = try await workspace.listFiles(limit: 150)
        return try XCTUnwrap(initial.first { sourceContents[$0.path] != nil }?.path)
    }

    private static func source(index: Int) -> String {
        switch index {
        case 0:
            return """
            // \(earlyEvidence)
            struct Feature0 {
                func retry(_ operation: () async throws -> String) async -> String {
                    while true {
                        do {
                            return try await operation()
                        } catch {
                            continue
                        }
                    }
                }
            }
            """ + "\n"
        case sourceCount - 1:
            return """
            // \(lateEvidence)
            final class Feature599 {
                private(set) var history: [String] = []
                func observe(_ entry: String) {
                    history.append(entry)
                }
            }
            """ + "\n"
        default:
            return """
            // Independent feature \(index)
            struct Feature\(index) {
                let identifier = \(index)
                func displayName() -> String { "Feature \(index)" }
            }
            """ + "\n"
        }
    }
}
