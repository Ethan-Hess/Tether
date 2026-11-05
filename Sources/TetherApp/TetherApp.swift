import AppKit
import SwiftUI
import TetherKit

@main
struct TetherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = BottleListModel()

    var body: some Scene {
        WindowGroup("Tether") {
            BottleListView()
                .environment(model)
                .frame(minWidth: 720, minHeight: 440)
        }
        Settings {
            SettingsView()
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

@Observable
final class BottleListModel {
    private let store = BottleStore()
    let profiles = ProfileLibrary.load()
    var bottles: [Bottle] = []
    var selection: Bottle.ID?
    var error: String?

    init() { reload() }

    func reload() {
        do { bottles = try store.list() } catch { self.error = error.localizedDescription }
    }

    func create(name: String, profileID: String?) {
        do {
            let b = try store.create(name: name, config: BottleConfig(profileID: profileID))
            reload()
            selection = b.id
        } catch {
            self.error = error.localizedDescription
        }
    }

    func save(_ bottle: Bottle) {
        do { try store.save(bottle); reload() } catch { self.error = error.localizedDescription }
    }

    func delete(_ bottle: Bottle) {
        do { try store.delete(name: bottle.name); selection = nil; reload() } catch { self.error = error.localizedDescription }
    }
}
