import AppKit
import Observation
import ServiceManagement
import SwiftUI

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case overview, cpu, gpu, memory, storage, sensors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .cpu: "CPU"
        case .gpu: "Graphics"
        case .memory: "Memory"
        case .storage: "Storage"
        case .sensors: "All Sensors"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .cpu: "cpu"
        case .gpu: "rectangle.3.group"
        case .memory: "memorychip"
        case .storage: "internaldrive"
        case .sensors: "list.bullet.rectangle"
        }
    }

    var kind: ComponentKind? {
        switch self {
        case .cpu: .cpu
        case .gpu: .gpu
        case .memory: .memory
        case .storage: .storage
        default: nil
        }
    }

    static func item(for kind: ComponentKind) -> SidebarItem {
        switch kind {
        case .cpu: .cpu
        case .gpu: .gpu
        case .memory: .memory
        case .storage: .storage
        }
    }

    /// ⌘1 … ⌘6
    var shortcut: KeyEquivalent { KeyEquivalent(Character("\((Self.allCases.firstIndex(of: self) ?? 0) + 1)")) }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum MenuBarSource: String, CaseIterable, Identifiable {
    case cpu, gpu, storage, hottest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "Graphics"
        case .storage: "Internal SSD"
        case .hottest: "Hottest component"
        }
    }
}

struct Toast: Identifiable, Equatable {
    enum Style { case success, info, error }
    let id = UUID()
    let message: String
    var style: Style = .success
    var actionTitle: String?
    var action: (() -> Void)?

    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

/// App-wide state: settings (persisted), navigation, transient UI.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let monitor = MonitorStore()

    var selection: SidebarItem? = .overview
    var searchText = ""
    var toast: Toast?
    var isConfirmingReset = false

    // Persisted settings.
    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: "appearance"); applyAppearance() } }
    var fahrenheit: Bool { didSet { defaults.set(fahrenheit, forKey: "fahrenheit") } }
    var alwaysOnTop: Bool { didSet { defaults.set(alwaysOnTop, forKey: "alwaysOnTop") } }
    var showInMenuBar: Bool { didSet { defaults.set(showInMenuBar, forKey: "showInMenuBar") } }
    var menuBarSource: MenuBarSource { didSet { defaults.set(menuBarSource.rawValue, forKey: "menuBarSource") } }
    private(set) var startAtLogin = SMAppService.mainApp.status == .enabled

    /// Set by the main window so the menu bar and Dock can reopen it.
    @ObservationIgnored var openMainWindow: (() -> Void)?
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    private init() {
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        fahrenheit = defaults.bool(forKey: "fahrenheit")
        alwaysOnTop = defaults.bool(forKey: "alwaysOnTop")
        showInMenuBar = defaults.object(forKey: "showInMenuBar") as? Bool ?? true
        menuBarSource = MenuBarSource(rawValue: defaults.string(forKey: "menuBarSource") ?? "") ?? .cpu
    }

    /// Applies the theme to every window, menu and popover immediately.
    func applyAppearance() { NSApp.appearance = appearance.nsAppearance }

    func temp(_ c: Double) -> String { Format.temp(c, fahrenheit: fahrenheit) }

    // MARK: - Login item

    func setStartAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            show(Toast(message: "Couldn't change the login item: \(error.localizedDescription)", style: .error))
        }
        startAtLogin = service.status == .enabled
        if on && service.status == .requiresApproval {
            show(Toast(message: "Allow Temp Monitor in Login Items to finish.", style: .info,
                       actionTitle: "Open Settings", action: { SMAppService.openSystemSettingsLoginItems() }))
        }
    }

    func refreshLoginState() { startAtLogin = SMAppService.mainApp.status == .enabled }

    // MARK: - Actions

    func show(_ t: Toast) {
        toast = t
        AccessibilityNotification.Announcement(t.message).post()
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(t.action == nil ? 3.5 : 6))
            guard !Task.isCancelled, self?.toast?.id == t.id else { return }
            self?.toast = nil
        }
    }

    func saveDiagnostics() {
        Task {
            let report = await monitor.withSensors { $0.diagnosticReport() }
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            let url = desktop.appendingPathComponent("TempMonitor-diagnostics.txt")
            do {
                try report.write(to: url, atomically: true, encoding: .utf8)
                show(Toast(message: "Diagnostics saved to your Desktop", actionTitle: "Show in Finder",
                           action: { NSWorkspace.shared.activateFileViewerSelecting([url]) }))
            } catch {
                show(Toast(message: "Couldn't save diagnostics: \(error.localizedDescription)", style: .error))
            }
        }
    }

    func resetStatistics() {
        monitor.resetStatistics()
        show(Toast(message: "Min, max and history cleared", style: .info))
    }

    func summaryText(for cards: [CardState]? = nil) -> String {
        (cards ?? monitor.cards).map { c in
            let r = c.reading
            let t = r.temperature.map(temp) ?? "N/A"
            let u = r.usage.map { String(format: "%.0f%%", $0) } ?? "—"
            return "\(r.title) (\(r.device)): \(t), \(r.usageLabel.lowercased()) \(u)"
        }.joined(separator: "\n")
    }

    func copySummary(_ cards: [CardState]? = nil) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summaryText(for: cards), forType: .string)
        show(Toast(message: cards?.count == 1 ? "Reading copied" : "Summary copied", style: .info))
    }

    /// The reading shown in the menu bar.
    var menuBarReading: Reading? {
        let cards = monitor.cards
        switch menuBarSource {
        case .cpu: return cards.first { $0.reading.kind == .cpu }?.reading
        case .gpu: return cards.first { $0.reading.kind == .gpu && $0.reading.temperature != nil }?.reading
        case .storage: return cards.first { $0.reading.kind == .storage }?.reading
        case .hottest:
            return cards.compactMap { c in c.reading.temperature.map { (c.reading, $0) } }.max { $0.1 < $1.1 }?.0
        }
    }

    /// Cards matching the search field.
    func filtered(_ cards: [CardState]) -> [CardState] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return cards }
        return cards.filter {
            $0.reading.title.localizedCaseInsensitiveContains(q) || $0.reading.device.localizedCaseInsensitiveContains(q)
        }
    }
}
