import SwiftUI

struct OverviewView: View {
    var body: some View {
        ScrollView { OverviewContent() }
    }
}

struct OverviewContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cards = model.filtered(model.monitor.cards)
            VStack(alignment: .leading, spacing: Space.xl) {
                if model.searchText.isEmpty {
                    HealthSummary()
                }
                if let warning = model.monitor.warning {
                    Banner(message: warning)
                }
                if cards.isEmpty {
                    ContentUnavailableView.search(text: model.searchText)
                        .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: Space.l, alignment: .top)],
                              alignment: .leading, spacing: Space.l) {
                        ForEach(cards) { ComponentPanel(card: $0) }
                    }
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 1400, alignment: .leading)
    }
}

/// One line that says whether anything needs attention, plus the headline numbers.
struct HealthSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cards = model.monitor.cards
        let worst = cards.map(\.status).max() ?? .normal
        let hot = cards.filter { $0.status >= .warm }
        let headline: String = {
            if hot.isEmpty { return "Everything is running cool" }
            let names = hot.map(\.reading.title).joined(separator: ", ")
            return worst == .hot ? "\(names) \(hot.count == 1 ? "is" : "are") running hot" : "\(names) \(hot.count == 1 ? "is" : "are") warm"
        }()
        let status: TempStatus = hot.isEmpty ? .normal : worst

        HStack(alignment: .center, spacing: Space.l) {
            Image(systemName: status.symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(status.tint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(status.soft))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(headline).font(Typo.sectionTitle).foregroundStyle(Tokens.textPrimary)
                Text(subline(cards)).font(Typo.secondary).foregroundStyle(Tokens.textSecondary)
            }
            Spacer(minLength: Space.l)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.xl) { stats(cards) }
                EmptyView()
            }
        }
        .panel()
        .accessibilityElement(children: .combine)
    }

    private func subline(_ cards: [CardState]) -> String {
        let sensors = cards.filter { $0.reading.temperature != nil }.count
        var s = "\(sensors) of \(cards.count) components report a temperature"
        if let t = model.monitor.lastUpdate {
            s += " · updated \(t.formatted(date: .omitted, time: .standard))"
        }
        return s
    }

    @ViewBuilder private func stats(_ cards: [CardState]) -> some View {
        if let hottest = cards.compactMap({ c in c.reading.temperature.map { (c, $0) } }).max(by: { $0.1 < $1.1 }) {
            MetricBlock(title: "Hottest", value: model.temp(hottest.1), caption: hottest.0.reading.title,
                        font: Typo.metric, alignment: .trailing)
        }
        if let cpu = cards.first(where: { $0.reading.kind == .cpu }), let u = cpu.reading.usage {
            MetricBlock(title: "CPU load", value: String(format: "%.0f%%", u), caption: "all cores",
                        font: Typo.metric, alignment: .trailing)
        }
        if let fans = cards.first(where: { $0.reading.kind == .cpu })?.reading.details.first(where: { $0.label.hasPrefix("Fan") }) {
            MetricBlock(title: fans.label, value: fans.value.replacingOccurrences(of: " rpm", with: ""), caption: "rpm",
                        font: Typo.metric, alignment: .trailing)
        }
    }
}

/// A component on the Overview grid. Click (or Return/Space when focused) opens its page.
struct ComponentPanel: View {
    let card: CardState
    @Environment(AppModel.self) private var model

    private var r: Reading { card.reading }

    var body: some View {
        Button {
            model.selection = SidebarItem.item(for: r.kind)
        } label: {
            content
        }
        .buttonStyle(PanelButtonStyle())
        .focusEffectDisabled()
        .draggable(model.summaryText(for: [card]))
        .contextMenu {
            Button("Show Details", systemImage: "chart.xyaxis.line") { model.selection = SidebarItem.item(for: r.kind) }
            Button("Copy Reading", systemImage: "doc.on.doc") { model.copySummary([card]) }
            Divider()
            Button("Reset Statistics…", systemImage: "arrow.counterclockwise") { model.isConfirmingReset = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens \(r.title) details")
        .accessibilityAddTraits(.isButton)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            // Header
            HStack(alignment: .center, spacing: Space.s) {
                Image(systemName: r.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Tokens.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Tokens.backgroundSecondary))
                VStack(alignment: .leading, spacing: 0) {
                    Text(r.title).font(Typo.sectionTitle).foregroundStyle(Tokens.textPrimary)
                    Text(r.device).font(Typo.label).foregroundStyle(Tokens.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: Space.s)
                StatusBadge(status: card.status)
            }

            // Numbers
            HStack(alignment: .top) {
                MetricBlock(title: "Temperature", value: r.temperature.map(model.temp) ?? "—",
                            caption: r.temperature == nil ? r.temperatureUnavailableReason : r.temperatureSource,
                            reservesCaptionSpace: true)
                Spacer(minLength: Space.m)
                MetricBlock(title: r.usageLabel, value: r.usage.map { String(format: "%.0f%%", $0) } ?? "—",
                            alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                Meter(percent: r.usage)
                // Every panel keeps the secondary row's space so a grid row's panels line up.
                Group {
                    HStack {
                        Text(r.secondary == nil ? " " : r.secondaryLabel)
                        Spacer()
                        Text(r.secondary.map { (r.secondaryText.map { "\($0) · " } ?? "") + String(format: "%.0f%%", $0) } ?? "")
                            .monospacedDigit()
                    }
                    .font(Typo.label)
                    .foregroundStyle(Tokens.textSecondary)
                    Meter(percent: r.secondary, tint: Tokens.seriesSecondary, height: 4)
                }
                .opacity(r.secondary == nil ? 0 : 1)
                .accessibilityHidden(r.secondary == nil)
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                Sparkline(card: card).frame(height: 44)
                HStack(spacing: Space.m) {
                    if r.temperature != nil { LegendItem(title: "Temp", color: card.status.series) }
                    LegendItem(title: "Usage", color: Tokens.seriesUsage)
                    Spacer()
                    if let lo = card.minTemp, let hi = card.maxTemp {
                        Text("\(model.temp(lo)) – \(model.temp(hi))")
                            .font(Typo.metadata).foregroundStyle(Tokens.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityText: String {
        var parts = [r.title, r.device]
        if let t = r.temperature { parts.append("temperature \(model.temp(t)), \(card.status.label)") }
        else { parts.append("temperature unavailable, \(r.temperatureUnavailableReason ?? "")") }
        if let u = r.usage { parts.append("\(r.usageLabel) \(Int(u.rounded())) percent") }
        if let s = r.secondary { parts.append("\(r.secondaryLabel) \(Int(s.rounded())) percent") }
        return parts.joined(separator: ", ")
    }
}

struct Banner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(Typo.secondary)
            .foregroundStyle(Tokens.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.m)
            .background(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(Tokens.warningSoft))
    }
}
