import Foundation

enum ComponentKind: String, CaseIterable {
    case cpu, gpu, memory, storage
}

/// A labelled fact shown under a component, e.g. "Fans" → "5,610 / 5,211 rpm".
struct Detail: Hashable {
    let label: String
    let value: String
}

/// One card's worth of data, produced by `SensorService` once per refresh.
struct Reading: Identifiable {
    let key: String
    let title: String
    var device: String
    var kind: ComponentKind
    /// SF Symbol for the component.
    var symbol: String
    /// Sort order of the card in the window.
    var order: Int

    /// Temperature in °C, or nil when the hardware does not expose one.
    var temperature: Double?
    var temperatureSource = ""
    var temperatureUnavailableReason: String?

    /// Temperatures at or above these are shown amber / red.
    var warmAt: Double = 70
    var hotAt: Double = 85

    var usage: Double?
    var usageLabel = "Usage"

    /// Optional second bar, e.g. disk space used.
    var secondary: Double?
    var secondaryLabel = ""
    var secondaryText: String?

    var details: [Detail] = []

    var id: String { key }
}

/// One raw sensor for the Sensors table.
struct RawSensor: Identifiable, Hashable {
    let id: String
    let name: String
    let key: String
    let group: String
    let value: Double
    let unit: String

    var formatted: String {
        unit == "rpm" ? "\(Int(value.rounded()).formatted()) rpm" : String(format: "%.1f %@", value, unit)
    }
}

enum Format {
    static func temp(_ celsius: Double, fahrenheit: Bool) -> String {
        fahrenheit ? String(format: "%.0f °F", celsius * 9 / 5 + 32) : String(format: "%.0f °C", celsius)
    }

    static func bytes(_ b: Double) -> String {
        let gb = b / 1_000_000_000
        if gb >= 1000 { return String(format: "%.2f TB", gb / 1000) }
        if gb >= 100 { return String(format: "%.0f GB", gb) }
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", b / 1_000_000)
    }

    /// Memory sizes use binary units, like Activity Monitor.
    static func memory(_ b: Double) -> String {
        String(format: "%.1f GB", b / 1_073_741_824)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let mb = bytesPerSecond / 1_000_000
        return mb >= 10 ? String(format: "%.0f MB/s", mb) : String(format: "%.1f MB/s", mb)
    }
}
