import Darwin
import Foundation

/// CPU usage across all logical cores, from the kernel's per-core tick counters.
final class CPUUsage {
    private var previous: [(busy: UInt64, total: UInt64)] = []

    /// Percent busy since the previous call; nil on the first call.
    func sample() -> Double? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info
        else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        var current: [(busy: UInt64, total: UInt64)] = []
        for i in 0..<Int(count) {
            let base = Int(CPU_STATE_MAX) * i
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            current.append((user + system + nice, user + system + nice + idle))
        }
        defer { previous = current }
        guard previous.count == current.count else { return nil }

        var busy: UInt64 = 0, total: UInt64 = 0
        for (now, before) in zip(current, previous) {
            busy &+= now.busy &- before.busy
            total &+= now.total &- before.total
        }
        return total > 0 ? Double(busy) / Double(total) * 100 : nil
    }
}

/// Memory figures as Activity Monitor defines them.
struct MemoryStats {
    let total: Double
    /// "Memory Used" = app memory + wired + compressed.
    let used: Double
    let app: Double
    let wired: Double
    let compressed: Double
    let cached: Double
    let swapUsed: Double
    /// 0–100; derived from the kernel's "memory available" level.
    let pressure: Double?

    static func read() -> MemoryStats? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS, let total = Sysctl.int("hw.memsize") else { return nil }

        let page = Double(vm_kernel_page_size)
        let app = Double(stats.internal_page_count - stats.purgeable_count) * page
        let wired = Double(stats.wire_count) * page
        let compressed = Double(stats.compressor_page_count) * page
        let cached = Double(stats.external_page_count + stats.purgeable_count) * page

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let swapUsed = sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 ? Double(swap.xsu_used) : 0

        let level = Sysctl.int("kern.memorystatus_level")
        return MemoryStats(total: Double(total), used: app + wired + compressed, app: app, wired: wired,
                           compressed: compressed, cached: cached, swapUsed: swapUsed,
                           pressure: level.map { Double(max(0, min(100, 100 - $0))) })
    }
}
