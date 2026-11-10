import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section {
                row(.overview)
            }
            Section("Hardware") {
                ForEach([SidebarItem.cpu, .gpu, .memory, .storage]) { row($0) }
            }
            Section("Diagnostics") {
                row(.sensors)
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ item: SidebarItem) -> some View {
        let summary = summary(for: item)
        return Label {
            HStack {
                Text(item.title)
                Spacer(minLength: Space.s)
                if let summary {
                    HStack(spacing: Space.xs) {
                        if summary.status >= .warm {
                            Image(systemName: summary.status.symbol)
                                .foregroundStyle(summary.status.tint)
                                .imageScale(.small)
                        }
                        Text(summary.text)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(Typo.label)
                }
            }
        } icon: {
            Image(systemName: item.symbol)
        }
        .tag(item)
        .accessibilityLabel(summary.map { "\(item.title), \($0.text), \($0.status.label)" } ?? item.title)
        .contextMenu {
            if let kind = item.kind {
                Button("Copy Readings", systemImage: "doc.on.doc") { model.copySummary(model.monitor.cards(of: kind)) }
            }
        }
    }

    /// Hottest temperature in a group, for the trailing hint.
    private func summary(for item: SidebarItem) -> (text: String, status: TempStatus)? {
        guard let kind = item.kind else { return nil }
        let cards = model.monitor.cards(of: kind)
        guard let hottest = cards.filter({ $0.reading.temperature != nil })
            .max(by: { $0.reading.temperature! < $1.reading.temperature! }) else { return nil }
        let t = hottest.reading.temperature!
        let text = model.fahrenheit ? String(format: "%.0f°", t * 9 / 5 + 32) : String(format: "%.0f°", t)
        return (text, cards.map(\.status).max() ?? .normal)
    }
}
