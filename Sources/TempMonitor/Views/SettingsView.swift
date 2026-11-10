import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        .frame(width: 540)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { model.startAtLogin }, set: { model.setStartAtLogin($0) }))
                Text("Starts in the menu bar without opening the window.")
                    .font(Typo.label).foregroundStyle(Tokens.textSecondary)
                Toggle("Keep window on top of other apps", isOn: $model.alwaysOnTop)
            }
            Section("Menu bar") {
                Toggle("Show temperature in the menu bar", isOn: $model.showInMenuBar)
                Picker("Shows", selection: $model.menuBarSource) {
                    ForEach(MenuBarSource.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!model.showInMenuBar)
            }
            Section("Data") {
                LabeledContent("Diagnostics") {
                    Button("Save to Desktop") { model.saveDiagnostics() }
                }
                LabeledContent("Statistics") {
                    Button("Reset…") { model.isConfirmingReset = true; model.openMainWindow?() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshLoginState() }
    }
}

private struct AppearanceSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Theme") {
                HStack(spacing: Space.l) {
                    ForEach(AppearanceMode.allCases) { mode in
                        ThemeOption(mode: mode, selected: model.appearance == mode) { model.appearance = mode }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s)
            }
            Section("Units") {
                Picker("Temperature", selection: $model.fahrenheit) {
                    Text("Celsius (°C)").tag(false)
                    Text("Fahrenheit (°F)").tag(true)
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
    }
}

/// A miniature window in the theme's colours. Keyboard-focusable, announced as a
/// selectable button.
private struct ThemeOption: View {
    let mode: AppearanceMode
    let selected: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.s) {
                preview
                    .frame(width: 112, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                        .strokeBorder(selected ? Tokens.accent : Tokens.border, lineWidth: selected ? 2.5 : 1))
                    .overlay {
                        if focused {
                            RoundedRectangle(cornerRadius: Radius.tile + 3, style: .continuous)
                                .inset(by: -4).strokeBorder(Tokens.focus, lineWidth: 2.5)
                        }
                    }
                HStack(spacing: Space.xs) {
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Tokens.accent) }
                    Text(mode.title).foregroundStyle(Tokens.textPrimary)
                }
                .font(selected ? Typo.labelEmphasis : Typo.label)
            }
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .accessibilityLabel("\(mode.title) theme")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var preview: some View {
        switch mode {
        case .light: MiniWindow(dark: false)
        case .dark: MiniWindow(dark: true)
        case .system:
            HStack(spacing: 0) {
                MiniWindow(dark: false)
                MiniWindow(dark: true)
            }
        }
    }
}

/// Fixed colours on purpose: it depicts a theme, so it must not follow the current one.
private struct MiniWindow: View {
    let dark: Bool

    var body: some View {
        let p = { (s: Swatch) in Color(nsColor: NSColor(hex: dark ? s.dark : s.light)) }
        HStack(spacing: 0) {
            Rectangle().fill(p(Palette.backgroundSecondary)).frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 2).fill(p(Palette.textTertiary)).frame(width: 30, height: 4)
                RoundedRectangle(cornerRadius: 4).fill(p(Palette.surface))
                    .overlay(alignment: .bottomLeading) {
                        Capsule().fill(p(Palette.accent)).frame(width: 26, height: 3).padding(5)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(p(Palette.border)))
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(p(Palette.backgroundPrimary))
        }
        .accessibilityHidden(true)
    }
}
