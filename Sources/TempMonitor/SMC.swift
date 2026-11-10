import CSensors
import Foundation

/// The Mac's System Management Controller: CPU, GPU, memory, SSD and fan sensors.
/// Reading needs no special rights. Not thread-safe; used only from the sensor queue.
final class SMC {
    struct Value {
        let type: String
        let bytes: [UInt8]

        /// Decodes the numeric SMC data types; nil for anything else.
        var number: Double? {
            let b = bytes
            switch type {
            case "flt ":
                guard b.count >= 4 else { return nil }
                return Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
            case "ui8 ": return b.count >= 1 ? Double(b[0]) : nil
            case "ui16": return b.count >= 2 ? Double(UInt16(b[0]) << 8 | UInt16(b[1])) : nil
            case "ui32":
                guard b.count >= 4 else { return nil }
                return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
            case "si8 ": return b.count >= 1 ? Double(Int8(bitPattern: b[0])) : nil
            case "si16": return b.count >= 2 ? Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) : nil
            default:
                // Fixed point: "spXY" (signed) / "fpXY" (unsigned), Y = fraction bits in hex.
                guard b.count >= 2, type.count == 4, type.hasPrefix("sp") || type.hasPrefix("fp"),
                      let frac = Int(String(type.last!), radix: 16)
                else { return nil }
                let raw = UInt16(b[0]) << 8 | UInt16(b[1])
                let v = type.hasPrefix("sp") ? Double(Int16(bitPattern: raw)) : Double(raw)
                return v / Double(1 << frac)
            }
        }
    }

    private(set) var isOpen = false

    init() { isOpen = smc_open() == 0 }

    deinit { smc_close() }

    func read(_ key: String) -> Value? {
        guard isOpen else { return nil }
        var type = [CChar](repeating: 0, count: 5)
        var bytes = [UInt8](repeating: 0, count: 32)
        var size: UInt32 = 0
        guard smc_read(key, &type, &bytes, &size) == 0 else { return nil }
        return Value(type: String(cString: type), bytes: Array(bytes.prefix(Int(size))))
    }

    func number(_ key: String) -> Double? { read(key)?.number }

    /// A plausible temperature, or nil (absent sensor, powered-down part, or junk value).
    func temperature(_ key: String) -> Double? {
        guard let v = number(key), v > 5, v < 130 else { return nil }
        return v
    }

    func allKeys() -> [String] {
        var count: UInt32 = 0
        guard isOpen, smc_key_count(&count) == 0 else { return [] }
        var keys: [String] = []
        var name = [CChar](repeating: 0, count: 5)
        for i in 0..<count where smc_key_at(i, &name) == 0 {
            keys.append(String(cString: name))
        }
        return keys
    }

    /// Plain-English names for well-known SMC keys on Intel Macs.
    static func describe(_ key: String) -> String {
        let known: [String: String] = [
            "TC0P": "CPU proximity", "TC0D": "CPU die", "TC0E": "CPU die (PECI, filtered)",
            "TC0F": "CPU die (PECI)", "TCXC": "CPU package (PECI)", "TCMX": "CPU hottest core",
            "TCGC": "Integrated GPU (PECI)", "TCSA": "CPU system agent", "TC0H": "CPU heatsink",
            "TG0P": "GPU proximity", "TG0D": "GPU die", "TGDD": "GPU die (discrete)",
            "TM0P": "Memory proximity", "TM0S": "Memory slot", "TB0T": "Battery", "TB1T": "Battery 1",
            "TB2T": "Battery 2", "TA0V": "Ambient", "TW0P": "Wi-Fi module", "TPCD": "Platform controller die",
            "Ts0P": "Palm rest", "Ts1P": "Palm rest 2", "TTLD": "Thunderbolt left", "TTRD": "Thunderbolt right",
        ]
        if let k = known[key] { return k }
        let c = Array(key)
        if c.count == 4, c[0] == "T", c[1] == "C", c[3] == "C", c[2].isNumber { return "CPU core \(c[2])" }
        if key.hasPrefix("TH") { return "SSD / storage" }
        if key.hasPrefix("TG") { return "GPU" }
        if key.hasPrefix("TC") { return "CPU" }
        if key.hasPrefix("TB") { return "Battery" }
        if c.count == 4, c[0] == "F", c[1].isNumber {
            switch key.suffix(2) {
            case "Ac": return "Fan \(c[1]) speed"
            case "Mn": return "Fan \(c[1]) minimum"
            case "Mx": return "Fan \(c[1]) maximum"
            case "Tg": return "Fan \(c[1]) target"
            default: return "Fan \(c[1])"
            }
        }
        return ""
    }
}
