import AppKit
import SwiftUI
import TetherKit

@main
struct TetherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Tether") {
            BottleListView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 480)
        }
        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Lets the app show a window and Dock icon when launched with `swift run` (no .app bundle).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
