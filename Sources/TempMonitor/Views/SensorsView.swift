import SwiftUI

/// Every raw SMC / HID / NVMe sensor, sortable and searchable.
struct SensorsView: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder = [KeyPathComparator(\RawSensor.group), KeyPathComparator(\RawSensor.key)]
    @State private var selection = Set<RawSensor.ID>()

    var body: some View {
        let rows = filtered.sorted(using: sortOrder)
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "All Sensors",
                       subtitle: "\(model.monitor.rawSensors.count) sensors · updated every second")
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.l)
            Divider().overlay(Tokens.border)
            if model.monitor.rawSensors.isEmpty {
                ProgressView("Reading sensors…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                ContentUnavailableView.search(text: model.searchText).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table(rows)
            }
        }
        .onAppear { model.monitor.wantsRawSensors = true }
        .onDisappear { model.monitor.wantsRawSensors = false }
    }

    private func table(_ rows: [RawSensor]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Sensor", value: \.name) { s in
                Text(s.name).foregroundStyle(s.name == "Unlabelled sensor" ? Tokens.textSecondary : Tokens.textPrimary)
            }
            .width(min: 160, ideal: 240)
            TableColumn("Group", value: \.group).width(min: 70, ideal: 90)
            TableColumn("Key", value: \.key) { s in Text(s.key).font(Typo.mono) }
                .width(min: 60, ideal: 80)
            TableColumn("Value", value: \.value) { s in
                Text(s.unit == "°C" ? model.temp(s.value) : s.formatted)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 100)
        }
        .contextMenu(forSelectionType: RawSensor.ID.self) { ids in
            Button("Copy", systemImage: "doc.on.doc") { copy(ids.isEmpty ? selection : ids) }
                .disabled(ids.isEmpty && selection.isEmpty)
        }
        .onCopyCommand { [text(selection)].map { NSItemProvider(object: $0 as NSString) } }
    }

    private var filtered: [RawSensor] {
        let q = model.searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return model.monitor.rawSensors }
        return model.monitor.rawSensors.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.key.localizedCaseInsensitiveContains(q)
                || $0.group.localizedCaseInsensitiveContains(q)
        }
    }

    private func text(_ ids: Set<RawSensor.ID>) -> String {
        model.monitor.rawSensors.filter { ids.contains($0.id) }
            .map { "\($0.key)\t\($0.name)\t\($0.unit == "°C" ? model.temp($0.value) : $0.formatted)" }
            .joined(separator: "\n")
    }

    private func copy(_ ids: Set<RawSensor.ID>) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text(ids), forType: .string)
        model.show(Toast(message: ids.count == 1 ? "Sensor copied" : "\(ids.count) sensors copied", style: .info))
    }
}
