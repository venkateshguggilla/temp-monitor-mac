import Charts
import SwiftUI

enum TimeWindow: Int, CaseIterable, Identifiable {
    case oneMinute = 60, twoMinutes = 120, fiveMinutes = 300
    var id: Int { rawValue }
    var title: String { "\(rawValue / 60) min" }
}

/// Every component of one kind, each with full-size history charts.
struct ComponentDetailView: View {
    let item: SidebarItem

    var body: some View {
        ScrollView { ComponentDetailContent(item: item) }
    }
}

struct ComponentDetailContent: View {
    let item: SidebarItem
    @Environment(AppModel.self) private var model
    @AppStorage("timeWindow") private var window = TimeWindow.twoMinutes

    var body: some View {
        let cards = model.filtered(item.kind.map(model.monitor.cards(of:)) ?? [])
            VStack(alignment: .leading, spacing: Space.xl) {
                PageHeader(title: item.title, subtitle: subtitle(cards)) {
                    Picker("History", selection: $window) {
                        ForEach(TimeWindow.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .help("How much history the charts show")
                }
                if cards.isEmpty {
                    if model.searchText.isEmpty {
                        ContentUnavailableView("Nothing to show", systemImage: item.symbol,
                                               description: Text("This Mac didn't report any \(item.title.lowercased()) hardware."))
                            .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        ContentUnavailableView.search(text: model.searchText)
                            .frame(maxWidth: .infinity, minHeight: 320)
                    }
                } else {
                    ForEach(cards) { DetailPanel(card: $0, window: window) }
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 1100, alignment: .leading)
    }

    private func subtitle(_ cards: [CardState]) -> String {
        cards.count == 1 ? cards[0].reading.device : "\(cards.count) devices"
    }
}

struct DetailPanel: View {
    let card: CardState
    let window: TimeWindow
    @Environment(AppModel.self) private var model

    private var r: Reading { card.reading }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .center, spacing: Space.s) {
                Image(systemName: r.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Tokens.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Tokens.backgroundSecondary))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(r.title).font(Typo.sectionTitle).foregroundStyle(Tokens.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(r.device).font(Typo.label).foregroundStyle(Tokens.textSecondary)
                }
                Spacer()
                StatusBadge(status: card.status)
                Button("Copy", systemImage: "doc.on.doc") { model.copySummary([card]) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Copy this reading")
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Space.l) { tiles }
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Space.m) { tiles }
            }

            if r.temperature != nil || card.temps.contains(where: { $0 != nil }) {
                ChartBlock(title: "Temperature", legend: card.status.series) {
                    TemperatureChart(card: card, window: window, fahrenheit: model.fahrenheit)
                }
            }
            if r.usage != nil {
                ChartBlock(title: r.usageLabel, legend: Tokens.seriesUsage) {
                    UsageChart(values: card.usages, window: window)
                }
            }

            if !r.details.isEmpty {
                Divider().overlay(Tokens.border)
                DetailList(details: r.details)
            }
        }
        .panel(padding: Space.xl)
    }

    @ViewBuilder private var tiles: some View {
        Tile {
            MetricBlock(title: "Temperature", value: r.temperature.map(model.temp) ?? "—",
                        caption: r.temperature == nil ? r.temperatureUnavailableReason : r.temperatureSource)
        }
        Tile {
            MetricBlock(title: r.usageLabel, value: r.usage.map { String(format: "%.0f%%", $0) } ?? "—")
        }
        if let s = r.secondary {
            Tile {
                MetricBlock(title: r.secondaryLabel, value: String(format: "%.0f%%", s), caption: r.secondaryText)
            }
        }
        Tile {
            MetricBlock(title: "Range this session",
                        value: card.minTemp.map { "\(model.temp($0)) – \(model.temp(card.maxTemp ?? $0))" } ?? "—",
                        caption: "Warm at \(model.temp(r.warmAt)) · hot at \(model.temp(r.hotAt))",
                        font: Typo.metric)
        }
    }
}

private struct Tile<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Space.m)
            .background(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(Tokens.backgroundSecondary))
    }
}

private struct ChartBlock<Content: View>: View {
    let title: String
    let legend: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            LegendItem(title: title, color: legend)
            content().frame(height: 150)
        }
    }
}

private struct Point: Identifiable {
    let id: Int
    let secondsAgo: Int
    let value: Double
}

private func points(_ values: [Double?], window: TimeWindow, transform: (Double) -> Double = { $0 }) -> [Point] {
    let recent = values.suffix(window.rawValue)
    let n = recent.count
    return recent.enumerated().compactMap { i, v in
        v.map { Point(id: i, secondsAgo: i - n + 1, value: transform($0)) }
    }
}

private struct TemperatureChart: View {
    let card: CardState
    let window: TimeWindow
    let fahrenheit: Bool

    private func convert(_ c: Double) -> Double { fahrenheit ? c * 9 / 5 + 32 : c }

    var body: some View {
        let data = points(card.temps, window: window, transform: convert)
        let warm = convert(card.reading.warmAt), hot = convert(card.reading.hotAt)
        let values = data.map(\.value)
        let lo = min(values.min() ?? convert(25), convert(25)) - 2
        let hi = max(values.max() ?? hot, hot) + 3
        let unit = fahrenheit ? "°F" : "°C"
        Chart {
            RuleMark(y: .value("Warm", warm))
                .foregroundStyle(Tokens.warning)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Warm").font(Typo.label).foregroundStyle(Tokens.warning)
                }
            RuleMark(y: .value("Hot", hot))
                .foregroundStyle(Tokens.danger)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Hot").font(Typo.label).foregroundStyle(Tokens.danger)
                }
            ForEach(data) { p in
                LineMark(x: .value("Seconds ago", p.secondsAgo), y: .value("Temperature", p.value))
                    .foregroundStyle(card.status.series)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: -(window.rawValue - 1)...0)
        .chartYScale(domain: lo...hi)
        .chartXAxis { timeAxis }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine().foregroundStyle(Tokens.gridline)
                AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))\(unit)") } }
                    .foregroundStyle(Tokens.textSecondary)
            }
        }
        .accessibilityLabel("\(card.reading.title) temperature history")
    }
}

private struct UsageChart: View {
    let values: [Double?]
    let window: TimeWindow

    var body: some View {
        Chart(points(values, window: window)) { p in
            AreaMark(x: .value("Seconds ago", p.secondsAgo), y: .value("Usage", p.value))
                .foregroundStyle(Tokens.seriesUsage.opacity(0.12))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Seconds ago", p.secondsAgo), y: .value("Usage", p.value))
                .foregroundStyle(Tokens.seriesUsage)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
        }
        .chartXScale(domain: -(window.rawValue - 1)...0)
        .chartYScale(domain: 0...100)
        .chartXAxis { timeAxis }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { v in
                AxisGridLine().foregroundStyle(Tokens.gridline)
                AxisValueLabel { if let d = v.as(Int.self) { Text("\(d)%") } }
                    .foregroundStyle(Tokens.textSecondary)
            }
        }
    }
}

@AxisContentBuilder private var timeAxis: some AxisContent {
    AxisMarks(values: .automatic(desiredCount: 5)) { v in
        AxisGridLine().foregroundStyle(Tokens.gridline)
        AxisValueLabel {
            if let s = v.as(Int.self) { Text(s == 0 ? "now" : "\(s)s") }
        }
        .foregroundStyle(Tokens.textSecondary)
    }
}
