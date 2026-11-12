import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

final class VyronOfficePreferencesTests: XCTestCase {
    func testMissingPreferenceUsesAutomaticRuntimeDiscoveryWithoutPersistingAPath() throws {
        let name = "VyronOfficePreferences-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertEqual(VyronOfficePreferences.configuration(defaults: defaults), VyronOfficeConfiguration())
        XCTAssertNil(defaults.object(forKey: VyronUserDefaultsKey.officePythonExecutable.rawValue))
    }

    func testConfiguredInterpreterIsCapturedForNewTasksWithoutChangingPreviousSnapshot() throws {
        let name = "VyronOfficePreferences-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let firstPath = "/Applications/Office Environment/bin/python3"
        defaults.set(firstPath, forKey: VyronUserDefaultsKey.officePythonExecutable.rawValue)
        let original = VyronOfficePreferences.configuration(defaults: defaults)

        defaults.set("/opt/another-environment/bin/python3", forKey: VyronUserDefaultsKey.officePythonExecutable.rawValue)
        let updated = VyronOfficePreferences.configuration(defaults: defaults)

        XCTAssertEqual(original.pythonExecutable, firstPath)
        XCTAssertEqual(updated.pythonExecutable, "/opt/another-environment/bin/python3")
        XCTAssertNotEqual(original, updated)
    }
}
