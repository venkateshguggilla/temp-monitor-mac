import Foundation
import Observation

/// A card plus the history drawn for it.
struct CardState: Identifiable {
    /// Five minutes at one sample a second.
    static let historyLength = 300

    var reading: Reading
    var temps: [Double?] = []
    var usages: [Double?] = []
    var minTemp: Double?
    var maxTemp: Double?

    var id: String { reading.key }
    var status: TempStatus { TempStatus(reading) }

    mutating func update(_ r: Reading) {
        reading = r
        if let t = r.temperature {
            minTemp = min(minTemp ?? t, t)
            maxTemp = max(maxTemp ?? t, t)
        }
        temps.append(r.temperature)
        usages.append(r.usage)
        if temps.count > Self.historyLength { temps.removeFirst(temps.count - Self.historyLength) }
        if usages.count > Self.historyLength { usages.removeFirst(usages.count - Self.historyLength) }
    }

    mutating func resetStatistics() {
        temps = []
        usages = []
        minTemp = nil
        maxTemp = nil
    }
}

/// Polls the sensors once a second on a background queue and publishes the cards.
@MainActor
@Observable
final class MonitorStore {
    static let interval: TimeInterval = 1

    private(set) var cards: [CardState] = []
    private(set) var lastUpdate: Date?
    private(set) var warning: String?
    /// Filled only while the Sensors table is on screen.
    private(set) var rawSensors: [RawSensor] = []
    @ObservationIgnored var wantsRawSensors = false {
        didSet { box.wantsRaw = wantsRawSensors }
    }

    var isReady: Bool { lastUpdate != nil }

    /// The service is created on, and only touched from, `queue`.
    private final class Box: @unchecked Sendable {
        var service: SensorService?
        var wantsRaw = false
    }

    @ObservationIgnored private let queue = DispatchQueue(label: "TempMonitor.sensors", qos: .utility)
    @ObservationIgnored private let box = Box()
    @ObservationIgnored private var timer: DispatchSourceTimer?

    func start() {
        guard timer == nil else { return }
        let box = box
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: Self.interval, leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in
            if box.service == nil {
                let s = SensorService()
                box.service = s
                let warning: String? = s.smc.isOpen || s.isAppleSilicon ? nil
                    : "Couldn't open the System Management Controller, so CPU, GPU and memory temperatures are unavailable."
                Task { @MainActor in self?.warning = warning }
            }
            let readings = box.service!.read()
            let raw = box.wantsRaw ? box.service!.rawSensors() : nil
            Task { @MainActor in self?.apply(readings, raw: raw) }
        }
        timer = t
        t.resume()
    }

    private func apply(_ readings: [Reading], raw: [RawSensor]?) {
        var byKey = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        var next: [CardState] = []
        for r in readings.sorted(by: { $0.order < $1.order }) {
            var c = byKey.removeValue(forKey: r.key) ?? CardState(reading: r)
            c.update(r)
            next.append(c)
        }
        cards = next // drives that were unplugged drop out here
        if let raw { rawSensors = raw }
        lastUpdate = Date()
    }

    func resetStatistics() {
        for i in cards.indices { cards[i].resetStatistics() }
    }

    func cards(of kind: ComponentKind) -> [CardState] { cards.filter { $0.reading.kind == kind } }

    /// Runs `work` on the sensor queue, between refreshes.
    func withSensors(_ work: @escaping @Sendable (SensorService) -> String) async -> String {
        let box = box
        return await withCheckedContinuation { cont in
            queue.async {
                cont.resume(returning: box.service.map(work) ?? "Sensors are still starting. Try again in a moment.")
            }
        }
    }
}
