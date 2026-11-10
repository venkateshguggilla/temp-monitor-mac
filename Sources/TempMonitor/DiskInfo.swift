import CSensors
import Foundation

/// A physical drive: one IOBlockStorageDriver plus the whole-disk media under it.
final class DiskInfo {
    let driver: IOObject
    let bsdName: String
    let model: String
    let size: Double
    let isSSD: Bool?
    let interconnect: String
    let isInternal: Bool
    /// The NVMe device above the driver, if the drive answers NVMe SMART queries.
    let nvme: IOObject?

    var key: String { "disk:\(driver.entryID)" }
    var isUSB: Bool { interconnect == "USB" }

    // Activity-time bookkeeping.
    private var lastTotals: (busyNs: UInt64, read: UInt64, written: UInt64)?
    private var lastSampleTime: TimeInterval = 0

    // SMART temperature cache (reading it is cheap, but not free on external drives).
    private(set) var smart: (temp: Int, sensors: [Int], wear: Int, at: Date)?
    private var nextSmart = Date.distantPast
    private(set) var smartFailed = false

    init?(driver: IOObject) {
        guard let media = driver.children.first(where: { $0.conforms(to: "IOMedia") }),
              (media.property("Whole") as? Bool) == true,
              let bsd = media.property("BSD Name") as? String,
              let size = (media.property("Size") as? NSNumber)?.doubleValue, size > 0,
              let device = driver.parent
        else { return nil }

        let chars = device.property("Device Characteristics") as? [String: Any] ?? [:]
        let proto = device.property("Protocol Characteristics") as? [String: Any] ?? [:]
        let interconnect = proto["Physical Interconnect"] as? String ?? ""
        // Mounted disk images and RAM disks are not hardware.
        guard interconnect != "Virtual Interface" else { return nil }

        self.driver = driver
        bsdName = bsd
        self.size = size
        let product = (chars["Product Name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let vendor = (chars["Vendor Name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        model = product.isEmpty ? (media.property("IOMediaName") as? String ?? bsd)
            : (vendor.isEmpty || product.lowercased().hasPrefix(vendor.lowercased()) ? product : "\(vendor) \(product)")
        switch chars["Medium Type"] as? String {
        case "Solid State": isSSD = true
        case "Rotational": isSSD = false
        default: isSSD = device.conforms(to: "IONVMeBlockStorageDevice") ? true : nil
        }
        self.interconnect = interconnect
        isInternal = (proto["Physical Interconnect Location"] as? String) == "Internal"
        nvme = device.conforms(to: "IONVMeBlockStorageDevice")
            && (device.property("NVMe SMART Capable") as? Bool) == true ? device : nil
    }

    /// Card title, e.g. "SSD", "USB HDD", "Thunderbolt SSD".
    var title: String {
        let medium = isSSD == true ? "SSD" : isSSD == false ? "HDD" : "Drive"
        if isInternal { return medium }
        switch interconnect {
        case "USB": return "USB \(medium)"
        case "Thunderbolt", "PCI-Express": return "External \(medium)"
        case "Secure Digital": return "SD card"
        default: return "External \(medium)"
        }
    }

    struct Activity {
        var activePercent: Double
        var readRate: Double
        var writeRate: Double
    }

    /// "Active time" like Task Manager / Activity Monitor: share of wall time the drive
    /// spent servicing I/O since the previous call.
    func sampleActivity() -> Activity? {
        guard let stats = driver.property("Statistics") as? [String: Any] else { return nil }
        func n(_ k: String) -> UInt64 { (stats[k] as? NSNumber)?.uint64Value ?? 0 }
        let totals = (busyNs: n("Total Time (Read)") &+ n("Total Time (Write)"),
                      read: n("Bytes (Read)"), written: n("Bytes (Write)"))
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastTotals = totals; lastSampleTime = now }
        guard let last = lastTotals, now > lastSampleTime else { return nil }
        let dt = now - lastSampleTime
        let busy = Double(totals.busyNs &- last.busyNs) / 1e9
        return Activity(activePercent: min(100, max(0, busy / dt * 100)),
                        readRate: Double(totals.read &- last.read) / dt,
                        writeRate: Double(totals.written &- last.written) / dt)
    }

    /// Re-reads NVMe SMART at most every `interval` seconds.
    func refreshSmart(interval: TimeInterval) {
        guard let nvme, Date() >= nextSmart else { return }
        nextSmart = Date().addingTimeInterval(interval)
        var temp: Int32 = 0, wear: Int32 = 0
        var sensors = [Int32](repeating: 0, count: 8)
        if nvme_smart_read(nvme.ref, &temp, &sensors, &wear) == 0, temp > 0, temp < 120 {
            smart = (Int(temp), sensors.map(Int.init).filter { $0 > 0 && $0 < 120 }, Int(wear), Date())
            smartFailed = false
        } else {
            smartFailed = true
        }
    }

    static func enumerate() -> [DiskInfo] {
        IOObject.matching("IOBlockStorageDriver").compactMap(DiskInfo.init)
    }

    /// Changes whenever a drive is attached or removed.
    static func signature() -> [UInt64] {
        IOObject.matching("IOBlockStorageDriver").map(\.entryID).sorted()
    }
}

/// Mounted file systems grouped by the physical drive they live on.
enum Volumes {
    struct Usage {
        var used: Double = 0
        var total: Double = 0
        var names: [String] = []
    }

    /// Keyed by the IOBlockStorageDriver registry ID. APFS volumes share their
    /// container's space, so each container is counted once.
    static func byDrive() -> [UInt64: Usage] {
        var mounts: UnsafeMutablePointer<statfs>?
        let n = getmntinfo(&mounts, MNT_NOWAIT)
        guard n > 0, let mounts else { return [:] }

        var result: [UInt64: Usage] = [:]
        var counted = Set<UInt64>()
        for i in 0..<Int(n) {
            var fs = mounts[i]
            let from = withUnsafeBytes(of: &fs.f_mntfromname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            let path = withUnsafeBytes(of: &fs.f_mntonname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            guard from.hasPrefix("/dev/disk"), let media = IOObject.bsd(String(from.dropFirst(5))) else { continue }

            let lineage = media.lineage
            guard let driver = lineage.first(where: { $0.conforms(to: "IOBlockStorageDriver") }) else { continue }
            let space = lineage.first(where: { $0.conforms(to: "AppleAPFSContainer") }) ?? media

            var u = result[driver.entryID] ?? Usage()
            if counted.insert(space.entryID).inserted {
                let bsize = Double(fs.f_bsize)
                u.total += Double(fs.f_blocks) * bsize
                u.used += Double(fs.f_blocks - fs.f_bfree) * bsize
            }
            // Name the volumes people see in Finder, not the system's hidden ones.
            let hidden = (fs.f_flags & UInt32(MNT_DONTBROWSE)) != 0
            if !hidden || path == "/" {
                let name = path == "/" ? (FileManager.default.displayName(atPath: "/")) : (path as NSString).lastPathComponent
                if !u.names.contains(name) { u.names.append(name) }
            }
            result[driver.entryID] = u
        }
        return result
    }
}
