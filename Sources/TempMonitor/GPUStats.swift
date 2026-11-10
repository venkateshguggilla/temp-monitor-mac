import Foundation

/// One graphics processor as IOKit's accelerator driver reports it.
final class GPUDevice {
    enum Kind { case discrete, integrated, apple }

    let service: IOObject
    let kind: Kind
    let name: String
    let vramTotal: Double?

    init(service: IOObject) {
        self.service = service
        let cls = service.className
        kind = cls.hasPrefix("AGX") ? .apple : cls.contains("Intel") ? .integrated : .discrete

        // The PCI device above the accelerator carries the marketing name and VRAM size.
        var name: String?
        var vram: Double?
        for e in service.lineage.prefix(4) {
            if name == nil, let d = e.property("model") as? Data {
                name = String(decoding: d, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
            } else if name == nil, let s = e.property("model") as? String {
                name = s
            }
            if vram == nil, let mb = e.property("VRAM,totalMB") as? NSNumber {
                vram = mb.doubleValue * 1_048_576
            }
        }
        self.name = name ?? (kind == .apple ? "Apple GPU" : "GPU")
        vramTotal = kind == .integrated || kind == .apple ? nil : vram
    }

    struct Sample {
        var utilization: Double?
        var vramUsed: Double?
    }

    /// Reads the driver's statistics. The AMD driver measures utilization since the
    /// previous query, so this must be called once per refresh and nowhere else.
    func sample() -> Sample {
        guard let stats = service.property("PerformanceStatistics") as? [String: Any] else { return Sample() }
        let util = (stats["Device Utilization %"] as? NSNumber)?.doubleValue
            ?? (stats["GPU Activity(%)"] as? NSNumber)?.doubleValue
        let vram = (stats["inUseVidMemoryBytes"] as? NSNumber)?.doubleValue
            ?? (stats["vramUsedBytes"] as? NSNumber)?.doubleValue
        return Sample(utilization: util.map { min(100, max(0, $0)) }, vramUsed: vram)
    }

    static func enumerate() -> [GPUDevice] {
        // The registry can list one accelerator under several paths; keep each once.
        var seen = Set<UInt64>()
        return IOObject.matching("IOAccelerator")
            .filter { seen.insert($0.entryID).inserted }
            .map(GPUDevice.init)
            .sorted { rank($0.kind) < rank($1.kind) }
    }

    private static func rank(_ k: Kind) -> Int {
        switch k { case .discrete: 0; case .apple: 1; case .integrated: 2 }
    }
}
