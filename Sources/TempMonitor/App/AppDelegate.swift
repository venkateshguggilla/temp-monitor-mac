import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // One copy at a time: a second launch (say, from a USB stick while the login copy
        // runs) brings the running one forward and quits.
        if let id = Bundle.main.bundleIdentifier,
           let other = NSRunningApplication.runningApplications(withBundleIdentifier: id)
               .first(where: { $0 != .current }) {
            other.activate()
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        model.applyAppearance()
        model.monitor.start()

        // Started at login: live in the menu bar until the user opens the window.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        if atLogin {
            DispatchQueue.main.async { Self.mainWindow?.close() }
        }
        Snapshot.scheduleIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            if let w = Self.mainWindow { w.makeKeyAndOrderFront(nil) } else { AppModel.shared.openMainWindow?() }
        }
        return true
    }

    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
    }
}

/// Dev aid: `--snapshot <file.png> [--appearance light|dark] [--section cpu]` renders the
/// main window to a PNG after a few refreshes, then quits.
enum Snapshot {
    @MainActor
    static func scheduleIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let path = args[i + 1]
        print("applied appearance: \(NSApp.appearance?.name.rawValue ?? "system")")
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }
        if let a = value("--appearance") { NSApp.appearance = AppearanceMode(rawValue: a)?.nsAppearance }
        if let s = value("--section").flatMap(SidebarItem.init(rawValue:)) { AppModel.shared.selection = s }
        let size = value("--size")?.split(separator: "x").compactMap { Double($0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if let size, size.count == 2, let w = AppDelegate.mainWindow {
                w.setContentSize(NSSize(width: size[0], height: size[1]))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
            defer { NSApp.terminate(nil) }
            // `--render`: draw just the page with ImageRenderer (deterministic; no window chrome).
            if args.contains("--render") {
                let model = AppModel.shared
                let page = Group {
                    switch model.selection ?? .overview {
                    case .overview: OverviewContent()
                    case .sensors: SensorsView()
                    case let item: ComponentDetailContent(item: item)
                    }
                }
                .environment(model)
                .environment(\.colorScheme, value("--appearance") == "dark" ? .dark : .light)
                .frame(width: size?.first ?? 960, height: size?.last ?? 900, alignment: .top)
                .background(Tokens.backgroundPrimary)
                let renderer = ImageRenderer(content: page)
                renderer.scale = 1
                var image: NSImage?
                (NSApp.appearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance { image = renderer.nsImage }
                if let image, let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
                return
            }
            guard let view = AppDelegate.mainWindow?.contentView?.superview,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
}
