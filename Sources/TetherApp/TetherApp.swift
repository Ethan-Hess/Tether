import AppKit
import SwiftUI
import TetherKit

@main
struct TetherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var updater = Updater()

    init() {
        // `Tether --self-check` reports what this copy can find and exits (used by packaging).
        if CommandLine.arguments.contains("--self-check") { SelfCheck.run() }
    }

    var body: some Scene {
        WindowGroup("Tether") {
            BottleListView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 480)
        }
        .commands { AppCommands(updater: updater) }
        Settings {
            SettingsView()
                .environment(model)
                .environment(updater)
        }
        Window("About Tether", id: "about") { AboutView() }
            .windowResizability(.contentSize)
        Window("Notices", id: "notices") { NoticesView() }
    }
}

/// Lets the app show a window and Dock icon when launched with `swift run` (no .app bundle).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct AppCommands: Commands {
    let updater: Updater
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Tether") { openWindow(id: "about") }
        }
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.isAvailable)
        }
        CommandGroup(after: .help) {
            Button("Notices") { openWindow(id: "notices") }
        }
    }
}
