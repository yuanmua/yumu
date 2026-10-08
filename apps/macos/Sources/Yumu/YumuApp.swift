import AppKit
import SwiftUI

@main
struct YumuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @AppStorage(Prefs.theme) private var theme = "system"

    init() {
        Prefs.register()
    }

    var body: some Scene {
        Window(L("app.name"), id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 620)
                .preferredColorScheme(ColorScheme.from(theme: theme))
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("instances.new")) { model.showingNew = true }.keyboardShortcut("n")
                Button(L("import.title")) { model.choosingImport = true }.keyboardShortcut("i")
            }
            CommandGroup(after: .sidebar) {
                Button(model.sidebarVisibility == .detailOnly ? L("sidebar.show") : L("sidebar.hide")) {
                    model.sidebarVisibility = model.sidebarVisibility == .detailOnly ? .all : .detailOnly
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                Button(L("running.title")) { model.page = .monitor }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(ColorScheme.from(theme: theme))
        }
    }
}

/// Keeps the main window alive: closing it hides it, and the Dock icon brings it back.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private weak var main: NSWindow?
    private weak var original: NSWindowDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) ?? NSApp.windows.first {
            main = window
            original = window.delegate
            window.isReleasedWhenClosed = false
            window.delegate = self
        }
    }

    // Everything except the close question still goes to SwiftUI's own delegate.
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            (main ?? NSApp.windows.first)?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
