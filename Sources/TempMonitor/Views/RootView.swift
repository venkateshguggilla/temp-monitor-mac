import SwiftUI

/// Main window: native split view (the sidebar and toolbar get macOS 26's glass for
/// free), detail pages, search, toasts and the reset confirmation.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tokens.backgroundPrimary)
                .navigationTitle(model.selection?.title ?? "Temp Monitor")
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: searchPrompt)
        .toolbar { MainToolbar() }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast) { model.toast = nil }
                    .padding(.bottom, Space.xl)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .animation(Motion.gentle(reduceMotion), value: model.toast)
        .confirmationDialog("Reset statistics?", isPresented: $model.isConfirmingReset) {
            Button("Reset Statistics", role: .destructive) { model.resetStatistics() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the minimum, maximum and history graphs for every component. Live readings continue.")
        }
        .background(WindowAccessor(alwaysOnTop: model.alwaysOnTop))
        .frame(minWidth: 760, minHeight: 500)
        .onAppear {
            model.openMainWindow = { openWindow(id: "main") }
            model.refreshLoginState()
        }
    }

    private var searchPrompt: String {
        model.selection == .sensors ? "Search sensors" : "Search components"
    }

    @ViewBuilder private var detail: some View {
        if !model.monitor.isReady {
            ProgressView {
                Text("Reading sensors…").font(Typo.secondary).foregroundStyle(Tokens.textSecondary)
            }
            .controlSize(.large)
        } else {
            switch model.selection ?? .overview {
            case .overview: OverviewView()
            case .sensors: SensorsView()
            case let item: ComponentDetailView(item: item)
            }
        }
    }
}

struct MainToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        @Bindable var model = model
        ToolbarItem(placement: .primaryAction) {
            Picker("Temperature unit", selection: $model.fahrenheit) {
                Text("°C").tag(false)
                Text("°F").tag(true)
            }
            .pickerStyle(.segmented)
            .help("Show temperatures in Celsius or Fahrenheit (⇧⌘U)")
        }
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $model.alwaysOnTop) {
                Label("Keep on Top", systemImage: model.alwaysOnTop ? "pin.fill" : "pin")
            }
            .help(model.alwaysOnTop ? "Stop keeping the window above others (⌥⌘T)" : "Keep the window above others (⌥⌘T)")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Copy Summary", systemImage: "doc.on.doc") { model.copySummary() }
                Button("Save Diagnostics", systemImage: "square.and.arrow.down") { model.saveDiagnostics() }
                Divider()
                Button("Reset Statistics…", systemImage: "arrow.counterclockwise") { model.isConfirmingReset = true }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("More actions")
        }
    }
}

/// Reaches the hosting NSWindow for the one thing SwiftUI can't do: window level.
struct WindowAccessor: NSViewRepresentable, Equatable {
    let alwaysOnTop: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let level: NSWindow.Level = alwaysOnTop ? .floating : .normal
        DispatchQueue.main.async { view.window?.level = level }
    }
}
