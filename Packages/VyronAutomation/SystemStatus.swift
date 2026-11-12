import Darwin
import Foundation

public struct SystemStatus: Sendable {
    public let sampledAt: Date
    public let cpuUtilization: Double?
    public let memoryTotalBytes: UInt64
    /// Free and speculative physical pages; excludes reclaimable file caches.
    public let memoryFreeBytes: UInt64
    public let diskTotalBytes: UInt64
    public let diskFreeBytes: UInt64
    public let thermalState: String
}

public enum SystemMonitorError: LocalizedError, Sendable {
    case unavailable

    public var errorDescription: String? { "Mac performance information is temporarily unavailable." }
}

/// Read-only kernel counters. No process contents, screen recording or network calls.
public actor SystemMonitor {
    private var previousCPU: [UInt32]?

    public init() {}

    public func sample() throws -> SystemStatus {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }

        var memory = vm_statistics64_data_t()
        var memoryCount = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let memoryResult = withUnsafeMutablePointer(to: &memory) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(memoryCount)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &memoryCount)
            }
        }
        var pageSize: vm_size_t = 0
        guard memoryResult == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS else {
            throw SystemMonitorError.unavailable
        }

        var cpu = host_cpu_load_info_data_t()
        var cpuCount = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let cpuResult = withUnsafeMutablePointer(to: &cpu) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &cpuCount)
            }
        }
        var utilization: Double?
        if cpuResult == KERN_SUCCESS {
            let ticks = withUnsafeBytes(of: cpu.cpu_ticks) { Array($0.bindMemory(to: UInt32.self)) }
            if let previousCPU, previousCPU.count == ticks.count {
                let differences = zip(ticks, previousCPU).map { UInt64($0 &- $1) }
                let total = differences.reduce(0, +)
                if total > 0 {
                    let idle = differences[Int(CPU_STATE_IDLE)]
                    utilization = min(1, max(0, Double(total - idle) / Double(total)))
                }
            }
            previousCPU = ticks
        }

        var disk = statfs()
        guard statfs("/System/Volumes/Data", &disk) == 0 else { throw SystemMonitorError.unavailable }
        let blockSize = UInt64(disk.f_bsize)
        let physical = ProcessInfo.processInfo.physicalMemory
        let freePages = UInt64(memory.free_count) + UInt64(memory.speculative_count)
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Normal"
        case .fair: thermal = "Warm"
        case .serious: thermal = "Hot"
        case .critical: thermal = "Very hot"
        @unknown default: thermal = "Unknown"
        }
        return SystemStatus(
            sampledAt: Date(),
            cpuUtilization: utilization,
            memoryTotalBytes: physical,
            memoryFreeBytes: min(physical, freePages * UInt64(pageSize)),
            diskTotalBytes: UInt64(disk.f_blocks) * blockSize,
            diskFreeBytes: UInt64(disk.f_bavail) * blockSize,
            thermalState: thermal
        )
    }
}
