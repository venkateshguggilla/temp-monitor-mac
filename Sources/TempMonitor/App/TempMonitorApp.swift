import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        // Command-line modes, handy for checking readings without the window:
        //   TempMonitor --dump / --diagnostics   card values plus every raw sensor
        //   TempMonitor --contrast-report        WCAG contrast of every palette pairing
        if args.contains("--dump") || args.contains("--diagnostics") {
            let sensors = SensorService()
            _ = sensors.read() // usage figures are deltas: prime them first
            Thread.sleep(forTimeInterval: 1)
            print(sensors.diagnosticReport())
            exit(0)
        }
        if args.contains("--contrast-report") {
            let (report, pass) = Contrast.report()
            print(report)
            exit(pass ? 0 : 1)
        }
        TempMonitorApp.main()
    }
}

struct TempMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("Temp Monitor", id: "main") {
            RootView()
                .environment(model)
        }
        .defaultSize(width: 1080, height: 760)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra(isInserted: Binding(get: { model.showInMenuBar }, set: { model.showInMenuBar = $0 })) {
            MenuBarContent()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
    }
}

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let r = model.menuBarReading
        HStack(spacing: 2) {
            Image(systemName: "thermometer.medium")
            Text(r?.temperature.map { model.fahrenheit ? String(format: "%.0f°", $0 * 9 / 5 + 32) : String(format: "%.0f°", $0) } ?? "–")
                .monospacedDigit()
        }
        .accessibilityLabel(r.flatMap { r in r.temperature.map { "\(r.title) \(model.temp($0))" } } ?? "Temp Monitor")
    }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(model.monitor.cards) { c in
            let r = c.reading
            let t = r.temperature.map(model.temp) ?? "No sensor"
            let u = r.usage.map { String(format: "%.0f%%", $0) } ?? "—"
            Button {
                model.selection = SidebarItem.item(for: r.kind)
                open()
            } label: {
                Label("\(r.title)   \(t)   ·   \(u)", systemImage: c.status >= .warm ? c.status.symbol : r.symbol)
            }
        }
        Divider()
        Button("Open Temp Monitor") { open() }
            .keyboardShortcut("o")
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Temp Monitor") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func open() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Save Diagnostics") { model.saveDiagnostics() }
                .keyboardShortcut("s")
            Button("Copy Summary") { model.copySummary() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
        }
        CommandGroup(before: .toolbar) {
            ForEach(SidebarItem.allCases) { item in
                Button(item.title) { model.selection = item }
                    .keyboardShortcut(item.shortcut)
            }
            Divider()
            Toggle("Show Fahrenheit", isOn: Binding(get: { model.fahrenheit }, set: { model.fahrenheit = $0 }))
                .keyboardShortcut("u", modifiers: [.command, .shift])
            Toggle("Keep Window on Top", isOn: Binding(get: { model.alwaysOnTop }, set: { model.alwaysOnTop = $0 }))
                .keyboardShortcut("t", modifiers: [.command, .option])
            Divider()
            Button("Reset Statistics…") { model.isConfirmingReset = true }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
        }
        CommandGroup(after: .sidebar) {
            Picker("Appearance", selection: Binding(get: { model.appearance }, set: { model.appearance = $0 })) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
            }
        }
    }
}
