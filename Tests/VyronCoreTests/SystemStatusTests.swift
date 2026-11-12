import XCTest
import VyronAutomation

final class SystemStatusTests: XCTestCase, @unchecked Sendable {
    func testActualMacCountersHaveValidRangesWithoutControlPermissions() async throws {
        let monitor = SystemMonitor()
        let initial = try await monitor.sample()
        XCTAssertGreaterThan(initial.memoryTotalBytes, 0)
        XCTAssertLessThanOrEqual(initial.memoryFreeBytes, initial.memoryTotalBytes)
        XCTAssertGreaterThan(initial.diskTotalBytes, 0)
        XCTAssertLessThanOrEqual(initial.diskFreeBytes, initial.diskTotalBytes)
        XCTAssertFalse(initial.thermalState.isEmpty)
        try await Task.sleep(for: .milliseconds(50))
        let next = try await monitor.sample()
        if let cpu = next.cpuUtilization {
            XCTAssertTrue(cpu.isFinite)
            XCTAssertTrue((0...1).contains(cpu))
        }
    }
}
