import Foundation
import XCTest
@testable import VyronCore

final class VyronScheduledProjectContextTests: XCTestCase {
    func testLegacyContextDecodesWithoutProjectIdentityAndKeepsWorkspace() throws {
        let legacy = context()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any]
        )
        object.removeValue(forKey: "projectPath")

        let decoded = try JSONDecoder().decode(
            VyronScheduledTaskContext.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(decoded.projectPath)
        XCTAssertEqual(decoded.workspacePath, "/Projects/SharedSource")
        XCTAssertEqual(decoded.mode, legacy.mode)
        XCTAssertEqual(decoded.model, legacy.model)
    }

    func testProjectIdentityAndExecutionFolderRoundTripSeparately() throws {
        var saved = context()
        saved.projectPath = "/Projects/ProjectIdentity"

        let data = try JSONEncoder().encode(saved)
        let decoded = try JSONDecoder().decode(VyronScheduledTaskContext.self, from: data)
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(decoded, saved)
        XCTAssertEqual(decoded.projectPath, "/Projects/ProjectIdentity")
        XCTAssertEqual(decoded.workspacePath, "/Projects/SharedSource")
        XCTAssertEqual(wire["workspacePath"] as? String, "/Projects/SharedSource")
        XCTAssertEqual(wire["projectPath"] as? String, "/Projects/ProjectIdentity")
    }

    func testProjectIdentityHasTheSamePathValidationAsExecutionFolder() throws {
        var record = task()
        record.definition.context.projectPath = "/Projects/ProjectIdentity"
        XCTAssertNoThrow(try record.validated())
        XCTAssertEqual(record.definition.context.workspacePath, "/Projects/SharedSource")

        for invalidPath in ["relative/path", "", "/Projects/Bad\nPath", String(repeating: "/", count: 4_097)] {
            record.definition.context.projectPath = invalidPath
            XCTAssertThrowsError(try record.validated()) { error in
                XCTAssertEqual(error as? VyronScheduledTaskError, .invalidTask)
            }
        }
        record.definition.context.projectPath = nil
        XCTAssertNoThrow(try record.validated())
    }

    private func context() -> VyronScheduledTaskContext {
        VyronScheduledTaskContext(
            workspacePath: "/Projects/SharedSource",
            mode: .plan,
            model: VyronScheduledModelSelection(
                connectionID: nil,
                model: "saved-model",
                automaticallySelect: false,
                effort: .automatic
            )
        )
    }

    private func task() -> VyronScheduledTask {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return VyronScheduledTask(
            id: UUID(),
            definition: VyronScheduledTaskDefinition(
                title: "Review project",
                prompt: "Inspect the selected source folder.",
                context: context()
            ),
            schedule: VyronTaskSchedule(startsAt: start, recurrence: .daily, timeZoneIdentifier: "Europe/Istanbul"),
            progress: VyronScheduledTaskProgress(isEnabled: true, nextRunAt: start, lastRun: nil)
        )
    }
}
