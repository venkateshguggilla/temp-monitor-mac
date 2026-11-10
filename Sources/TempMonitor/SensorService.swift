import CSensors
import Foundation

/// Reads every sensor and turns them into cards. Temperatures come from the hardware
/// itself: the SMC on Intel Macs, the SoC's HID sensors on Apple Silicon, and each
/// NVMe drive's own SMART log. Not thread-safe: use from one serial queue.
final class SensorService {
    let smc = SMC()
    let isAppleSilicon = Sysctl.int("hw.optional.arm64") == 1
    let cpuName: String
    let physicalCores: Int
    let logicalCores: Int

    private let cpu = CPUUsage()
    private let gpus: [GPUDevice]
    private var disks: [DiskInfo]
    private var diskSignature: [UInt64]
    private var nextDiskCheck = Date.distantPast
    private var volumes: [UInt64: Volumes.Usage] = [:]
    private var nextVolumeCheck = Date.distantPast

    // SMC keys this Mac actually has, resolved once at start-up.
    private let cpuKey: String?
    private let cpuCoreKeys: [String]
    private let cpuProximityKey: String?
    private let gpuKey: String?
    private let gpuProximityKey: String?
    private let igpuKey: String?
    private let memoryKey: String?
    private let ssdKeys: [String]
    private let fanCount: Int
    /// Temperature and fan-speed keys, listed once (enumerating all SMC keys is slow).
    private lazy var rawKeys: [String] = smc.allKeys().filter { $0.hasPrefix("T") || isFanSpeedKey($0) }

    init() {
        cpuName = Sysctl.string("machdep.cpu.brand_string")?
            .replacingOccurrences(of: "(R)", with: "").replacingOccurrences(of: "(TM)", with: "")
            .replacingOccurrences(of: "CPU @", with: "@").replacingOccurrences(of: "  ", with: " ") ?? "CPU"
        physicalCores = Sysctl.int("hw.physicalcpu") ?? 0
        logicalCores = Sysctl.int("hw.logicalcpu") ?? 0
        gpus = GPUDevice.enumerate()
        diskSignature = DiskInfo.signature()
        disks = DiskInfo.enumerate()

        let smc = self.smc
        func first(_ keys: [String]) -> String? { keys.first { smc.temperature($0) != nil } }
        cpuKey = first(["TCXC", "TC0F", "TC0E", "TC0D", "TC0P"])
        cpuCoreKeys = (0...15).map { String(format: "TC%XC", $0) }.filter { smc.temperature($0) != nil }
        cpuProximityKey = first(["TC0P"])
        gpuKey = first(["TGDD", "TG0D", "TGDF", "TG0P"])
        gpuProximityKey = first(["TG0P"])
        igpuKey = first(["TCGC"])
        memoryKey = first(["TM0P", "TM0S", "TM1P"])
        ssdKeys = ["TH0a", "TH0b", "TH0A", "TH0B", "TH0X", "TH0x", "TH0F", "TH1a", "TH1b"].filter { smc.temperature($0) != nil }
        fanCount = Int(smc.number("FNum") ?? 0)
    }

    // MARK: - Cards

    func read() -> [Reading] {
        refreshDisksIfChanged()
        if Date() >= nextVolumeCheck {
            volumes = Volumes.byDrive()
            nextVolumeCheck = Date().addingTimeInterval(5)
        }
        let hid = isAppleSilicon ? hidTemperatures() : [:]

        var out: [Reading] = [readCPU(hid: hid)]
        out += readGPUs(hid: hid)
        out.append(readMemory())
        out += disks.enumerated().map { readDisk($1, order: 100 + $0, hid: hid) }
        return out
    }

    private func readCPU(hid: [String: Double]) -> Reading {
        var r = Reading(key: "cpu", title: "CPU", device: cpuName, kind: .cpu, symbol: "cpu", order: 0,
                        warmAt: 80, hotAt: 95)
        r.usage = cpu.sample()
        r.details.append(Detail(label: "Cores", value: "\(physicalCores) cores · \(logicalCores) threads"))

        if let key = cpuKey, let t = smc.temperature(key) {
            r.temperature = t
            r.temperatureSource = key == "TC0P" ? "proximity sensor" : "package (PECI)"
            let cores = cpuCoreKeys.compactMap { smc.temperature($0) }
            if let lo = cores.min(), let hi = cores.max() {
                r.details.append(Detail(label: "Core range", value: String(format: "%.0f–%.0f °C", lo, hi)))
            }
            if key != "TC0P", let p = cpuProximityKey.flatMap(smc.temperature) {
                r.details.append(Detail(label: "Proximity", value: String(format: "%.0f °C", p)))
            }
        } else if let t = average(hid, matching: ["ACC MTR Temp", "PMU tdie", "SOC MTR Temp"]) {
            r.temperature = t
            r.temperatureSource = "average of die sensors"
            if let hi = maximum(hid, matching: ["ACC MTR Temp", "PMU tdie", "SOC MTR Temp"]) {
                r.details.append(Detail(label: "Hottest sensor", value: String(format: "%.0f °C", hi)))
            }
        } else {
            r.temperatureUnavailableReason = smc.isOpen ? "No CPU temperature sensor found" : "Could not open the SMC"
        }

        let fans = (0..<fanCount).compactMap { smc.number("F\($0)Ac") }.filter { $0 >= 0 && $0 < 20_000 }
        if !fans.isEmpty {
            r.details.append(Detail(label: fans.count == 1 ? "Fan" : "Fans",
                                    value: fans.map { Int($0.rounded()).formatted() }.joined(separator: " / ") + " rpm"))
        }
        return r
    }

    private func readGPUs(hid: [String: Double]) -> [Reading] {
        let discreteCount = gpus.filter { $0.kind == .discrete }.count
        return gpus.enumerated().map { index, gpu in
            let s = gpu.sample()
            let title = gpu.kind == .integrated && gpus.count > 1 ? "Integrated GPU"
                : gpu.kind == .discrete && discreteCount > 1 ? "GPU \(index + 1)" : "GPU"
            var r = Reading(key: "gpu:\(gpu.service.entryID)", title: title, device: gpu.name, kind: .gpu,
                            symbol: gpu.kind == .integrated ? "square.grid.3x3.square" : "rectangle.3.group",
                            order: 10 + index, warmAt: 75, hotAt: 90)
            r.usage = s.utilization

            switch gpu.kind {
            case .discrete:
                if let key = gpuKey, let t = smc.temperature(key) {
                    r.temperature = t
                    r.temperatureSource = key == "TG0P" ? "proximity sensor" : "die"
                    if key != "TG0P", let p = gpuProximityKey.flatMap(smc.temperature) {
                        r.details.append(Detail(label: "Proximity", value: String(format: "%.0f °C", p)))
                    }
                } else {
                    r.temperatureUnavailableReason = gpuKey == nil ? "No GPU temperature sensor found"
                        : "GPU is powered down (macOS is using the integrated GPU)"
                }
                if let used = s.vramUsed, let total = gpu.vramTotal, total > 0 {
                    r.secondary = min(100, used / total * 100)
                    r.secondaryLabel = "Video memory"
                    r.secondaryText = "\(Format.memory(used)) / \(Format.memory(total))"
                }
            case .integrated:
                if let key = igpuKey, let t = smc.temperature(key) {
                    r.temperature = t
                    r.temperatureSource = "die (PECI)"
                } else {
                    r.temperatureUnavailableReason = "No integrated-GPU sensor found"
                }
                r.details.append(Detail(label: "Memory", value: "Shared with system"))
            case .apple:
                if let t = average(hid, matching: ["GPU MTR Temp"]) {
                    r.temperature = t
                    r.temperatureSource = "average of die sensors"
                } else {
                    r.temperatureUnavailableReason = "No GPU temperature sensor found"
                }
                r.details.append(Detail(label: "Memory", value: "Unified"))
            }
            return r
        }
    }

    private func readMemory() -> Reading {
        let m = MemoryStats.read()
        var r = Reading(key: "ram", title: "Memory", device: m.map { Format.memory($0.total) } ?? "",
                        kind: .memory, symbol: "memorychip", order: 50, warmAt: 70, hotAt: 85)
        if isAppleSilicon { r.device += " unified memory" }

        if let key = memoryKey, let t = smc.temperature(key) {
            r.temperature = t
            r.temperatureSource = "memory proximity sensor"
        } else {
            r.temperatureUnavailableReason = isAppleSilicon
                ? "Memory is inside the Apple chip; it has no separate sensor"
                : "This Mac has no memory temperature sensor"
        }

        if let m {
            r.usage = m.used / m.total * 100
            r.usageLabel = "\(Format.memory(m.used)) of \(Format.memory(m.total)) used"
            if let p = m.pressure {
                r.secondary = p
                r.secondaryLabel = "Memory pressure"
            }
            r.details = [Detail(label: "App", value: Format.memory(m.app)),
                         Detail(label: "Wired", value: Format.memory(m.wired)),
                         Detail(label: "Compressed", value: Format.memory(m.compressed)),
                         Detail(label: "Cached files", value: Format.memory(m.cached))]
            if m.swapUsed > 0 { r.details.append(Detail(label: "Swap", value: Format.memory(m.swapUsed))) }
        }
        return r
    }

    private func readDisk(_ d: DiskInfo, order: Int, hid: [String: Double]) -> Reading {
        var r = Reading(key: d.key, title: d.title, device: "\(d.model) · \(Format.bytes(d.size))",
                        kind: .storage, symbol: d.isInternal ? "internaldrive" : "externaldrive",
                        order: order, warmAt: d.isSSD == false ? 45 : 60, hotAt: d.isSSD == false ? 55 : 70)

        d.refreshSmart(interval: d.isInternal ? 5 : 30)
        if let s = d.smart {
            r.temperature = Double(s.temp)
            r.temperatureSource = "drive's own sensor (NVMe SMART)"
            if !s.sensors.isEmpty {
                r.details.append(Detail(label: "Extra sensors", value: s.sensors.map { "\($0) °C" }.joined(separator: " / ")))
            }
            r.details.append(Detail(label: "Wear", value: "\(s.wear)%"))
        } else if d.isInternal, !ssdKeys.isEmpty, let t = ssdKeys.compactMap(smc.temperature).max() {
            r.temperature = t
            r.temperatureSource = "SSD sensor (SMC)"
        } else if d.isInternal, let t = average(hid, matching: ["NAND CH"]) {
            r.temperature = t
            r.temperatureSource = "NAND sensor"
        } else {
            r.temperatureUnavailableReason = d.isUSB ? "macOS doesn't pass SMART data through USB enclosures"
                : d.nvme != nil && d.smartFailed ? "Drive didn't answer the SMART query"
                : "Drive doesn't report temperature to macOS"
        }

        if let a = d.sampleActivity() {
            r.usage = a.activePercent
            r.details.insert(contentsOf: [Detail(label: "Read", value: Format.rate(a.readRate)),
                                          Detail(label: "Write", value: Format.rate(a.writeRate))], at: 0)
        }
        r.usageLabel = "Active time"

        if let v = volumes[d.driver.entryID], v.total > 0 {
            r.secondary = v.used / v.total * 100
            r.secondaryLabel = "Space used"
            r.secondaryText = "\(Format.bytes(v.used)) / \(Format.bytes(v.total))"
            if !v.names.isEmpty { r.details.append(Detail(label: "Volumes", value: v.names.joined(separator: ", "))) }
        } else {
            r.details.append(Detail(label: "Volumes", value: "None mounted"))
        }
        return r
    }

    private func refreshDisksIfChanged() {
        guard Date() >= nextDiskCheck else { return }
        nextDiskCheck = Date().addingTimeInterval(3)
        let sig = DiskInfo.signature()
        guard sig != diskSignature else { return }
        diskSignature = sig
        // Keep existing objects so activity deltas and SMART caches survive.
        let old = Dictionary(uniqueKeysWithValues: disks.map { ($0.driver.entryID, $0) })
        disks = DiskInfo.enumerate().map { old[$0.driver.entryID] ?? $0 }
        nextVolumeCheck = .distantPast
        volumes = Volumes.byDrive()
    }

    // MARK: - HID helpers (Apple Silicon)

    private func hidTemperatures() -> [String: Double] {
        var names = [CChar](repeating: 0, count: 128 * 64)
        var values = [Double](repeating: 0, count: 128)
        let n = hid_temperatures(&names, &values, 128)
        guard n > 0 else { return [:] }
        var out: [String: Double] = [:]
        for i in 0..<Int(n) where values[i] > 5 && values[i] < 130 {
            let name = names.withUnsafeBufferPointer { String(cString: $0.baseAddress! + i * 64) }
            out[name.isEmpty ? "sensor \(i)" : name] = values[i]
        }
        return out
    }

    private func matches(_ hid: [String: Double], _ patterns: [String]) -> [Double] {
        hid.filter { k, _ in patterns.contains { k.contains($0) } }.map(\.value)
    }

    private func average(_ hid: [String: Double], matching p: [String]) -> Double? {
        let v = matches(hid, p)
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    private func maximum(_ hid: [String: Double], matching p: [String]) -> Double? { matches(hid, p).max() }

    // MARK: - Raw sensors

    func rawSensors() -> [RawSensor] {
        var out: [RawSensor] = []
        for key in rawKeys {
            guard let n = smc.number(key) else { continue }
            let isTemp = key.hasPrefix("T")
            if isTemp, n <= 0 || n > 150 { continue }
            let desc = SMC.describe(key)
            out.append(RawSensor(id: "smc:\(key)", name: desc.isEmpty ? "Unlabelled sensor" : desc, key: key,
                                 group: isTemp ? group(forSMC: key) : "Fans", value: n, unit: isTemp ? "°C" : "rpm"))
        }
        for (name, v) in hidTemperatures() {
            out.append(RawSensor(id: "hid:\(name)", name: name, key: "HID", group: "SoC", value: v, unit: "°C"))
        }
        for d in disks {
            if let s = d.smart {
                out.append(RawSensor(id: "nvme:\(d.bsdName)", name: "\(d.model) composite", key: d.bsdName,
                                     group: "Storage", value: Double(s.temp), unit: "°C"))
            }
        }
        return out
    }

    private func group(forSMC key: String) -> String {
        switch key.prefix(2) {
        case "TC": return "CPU"
        case "TG": return "GPU"
        case "TM", "Tm": return "Memory"
        case "TH": return "Storage"
        case "TB": return "Battery"
        default: return "Chassis"
        }
    }

    // MARK: - Dumps

    /// Every temperature and fan sensor this Mac exposes, for comparison with other tools.
    func dumpAll() -> String {
        var lines: [String] = []
        if smc.isOpen {
            lines.append("SMC sensors")
            for key in smc.allKeys() where key.hasPrefix("T") || isFanSpeedKey(key) {
                guard let v = smc.read(key), let n = v.number else { continue }
                if key.hasPrefix("T"), n <= 0 || n > 150 { continue }
                let unit = key.hasPrefix("T") ? "°C" : "rpm"
                let desc = SMC.describe(key)
                lines.append(String(format: "  %@  %8.2f %@   %@", key, n, unit, desc))
            }
        }
        let hid = hidTemperatures()
        if !hid.isEmpty {
            lines.append("")
            lines.append("HID temperature sensors")
            for (k, v) in hid.sorted(by: { $0.key < $1.key }) { lines.append(String(format: "  %8.2f °C   %@", v, k)) }
        }
        lines.append("")
        lines.append("Drives")
        for d in disks {
            d.refreshSmart(interval: 0)
            let t = d.smart.map { "\($0.temp) °C (NVMe SMART), wear \($0.wear)%" } ?? "no SMART temperature"
            lines.append("  \(d.bsdName)  \(d.model)  [\(d.interconnect), \(d.isInternal ? "internal" : "external")]  \(t)")
        }
        lines.append("")
        lines.append("GPUs")
        for g in gpus {
            let s = g.sample()
            lines.append("  \(g.name)  [\(g.service.className)]  utilization \(s.utilization.map { String(format: "%.0f%%", $0) } ?? "n/a")")
        }
        return lines.joined(separator: "\n")
    }

    private func isFanSpeedKey(_ key: String) -> Bool {
        let c = Array(key)
        return c.count == 4 && c[0] == "F" && c[1].isNumber && ["Ac", "Mn", "Mx", "Tg"].contains(String(key.suffix(2)))
    }

    func diagnosticReport() -> String {
        var s = "TempMonitor diagnostics  \(Date())\n"
        s += "Mac: \(Sysctl.string("hw.model") ?? "?")  CPU: \(cpuName)  macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        s += "SMC open: \(smc.isOpen)  Apple Silicon: \(isAppleSilicon)\n"
        s += "Resolved keys: cpu=\(cpuKey ?? "-") cores=\(cpuCoreKeys) gpu=\(gpuKey ?? "-") igpu=\(igpuKey ?? "-") "
        s += "memory=\(memoryKey ?? "-") ssd=\(ssdKeys) fans=\(fanCount)\n\n"
        s += "==== Cards\n"
        for r in read() {
            let t = r.temperature.map { String(format: "%.1f °C (%@)", $0, r.temperatureSource) } ?? "N/A: \(r.temperatureUnavailableReason ?? "")"
            let u = r.usage.map { String(format: "%.1f%%", $0) } ?? "-"
            s += "\(r.title) [\(r.device)]  temp \(t)  \(r.usageLabel) \(u)"
            if let sec = r.secondary { s += String(format: "  %@ %.1f%%", r.secondaryLabel, sec) }
            s += "\n    \(r.details.map { "\($0.label) \($0.value)" }.joined(separator: " · "))\n"
        }
        s += "\n==== All sensors\n" + dumpAll() + "\n"
        return s
    }
}
