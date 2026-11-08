import AppKit
import Observation
import SwiftUI
import TetherKit

struct AlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// App-wide state. Long-running work (runtime download, first-run prefix setup, Steam install)
/// runs in TetherKit off the main actor; this class only holds results for the views.
@MainActor
@Observable
final class AppModel {
    let paths: TetherPaths
    let store: BottleStore
    let sessions: BottleSessions
    let profiles: ProfileLibrary
    let catalog = RuntimeCatalog.bundled()

    var bottles: [Bottle] = []
    var selection: Bottle.ID?
    var runtimes: [WineRuntime] = []
    var system = SystemCheck(items: [])
    var runningBottles: Set<String> = []
    /// What a bottle is busy with right now ("Starting…", "Installing Steam…"), if anything.
    var activity: [String: String] = [:]
    /// Policy and backend notes from each bottle's latest launch.
    var notices: [String: [String]] = [:]
    var isInstallingRuntime = false
    var alert: AlertInfo?

    init(paths: TetherPaths = .default) {
        self.paths = paths
        store = BottleStore(paths: paths)
        sessions = BottleSessions(launcher: Launcher(paths: paths))
        profiles = ProfileLibrary.load(paths: paths)
        reload()
        refreshSystem()
        Task { [weak self] in
            await self?.sessions.setObserver { [weak self] in
                Task { @MainActor in await self?.refreshRunning() }
            }
        }
    }

    // MARK: - state

    func reload() {
        do { bottles = try store.list() } catch { fail("Couldn't read bottles", error) }
    }

    func refreshSystem() {
        runtimes = RuntimeStore(paths: paths).list()
        system = SystemCheck.run(paths: paths)
    }

    func refreshRunning() async {
        runningBottles = await sessions.runningBottles()
    }

    var hasRuntime: Bool { !runtimes.isEmpty }
    var runtimeSource: RuntimeSource? { catalog.source(version: nil) }

    func bottle(_ id: Bottle.ID?) -> Bottle? { bottles.first { $0.id == id } }
    func isRunning(_ bottle: Bottle) -> Bool { runningBottles.contains(bottle.name) }
    func isBusy(_ bottle: Bottle) -> Bool { activity[bottle.name] != nil }

    func fail(_ title: String, _ error: Error) {
        alert = AlertInfo(title: title, message: error.localizedDescription)
    }

    // MARK: - runtime

    func installRuntime() {
        guard let source = runtimeSource, !isInstallingRuntime else { return }
        isInstallingRuntime = true
        Task {
            defer { isInstallingRuntime = false }
            do {
                try await RuntimeInstaller(paths: paths).install(source)
            } catch RuntimeInstallError.alreadyInstalled {
                // Nothing to do; the refresh below shows it.
            } catch {
                fail("Couldn't install the runtime", error)
            }
            refreshSystem()
        }
    }

    // MARK: - bottle management

    func create(name: String, config: BottleConfig) {
        do {
            let bottle = try store.create(name: name, config: config)
            reload()
            selection = bottle.id
        } catch { fail("Couldn't create the bottle", error) }
    }

    func save(_ bottle: Bottle) {
        do { try store.save(bottle); reload() } catch { fail("Couldn't save the bottle", error) }
    }

    func rename(_ bottle: Bottle, to newName: String) {
        do {
            let renamed = try store.rename(from: bottle.name, to: newName)
            notices[bottle.name] = nil
            reload()
            selection = renamed.id
        } catch { fail("Couldn't rename the bottle", error) }
    }

    func duplicate(_ bottle: Bottle, as newName: String) {
        activity[bottle.name] = "Copying…"
        let store = self.store
        Task {
            defer { activity[bottle.name] = nil }
            do {
                // A prefix can be large, so the copy runs off the main actor.
                let copy = try await Task.detached { try store.duplicate(name: bottle.name, as: newName) }.value
                reload()
                selection = copy.id
            } catch { fail("Couldn't duplicate the bottle", error) }
        }
    }

    func delete(_ bottle: Bottle) {
        guard !isRunning(bottle) else {
            alert = AlertInfo(title: "Bottle is running", message: "Stop '\(bottle.name)' before deleting it.")
            return
        }
        do {
            try store.delete(name: bottle.name)
            if selection == bottle.id { selection = nil }
            notices[bottle.name] = nil
            reload()
        } catch { fail("Couldn't delete the bottle", error) }
    }

    // MARK: - running

    func run(_ bottle: Bottle, executable: String, arguments: [String] = [], debug: Bool = false) {
        activity[bottle.name] = "Starting…"
        Task {
            defer { activity[bottle.name] = nil }
            do {
                let plan = try await sessions.start(
                    LaunchRequest(bottle: bottle, executable: executable, arguments: arguments, debug: debug)
                )
                notices[bottle.name] = LaunchNotices.messages(for: plan)
            } catch { fail("Couldn't start \(URL(fileURLWithPath: executable).lastPathComponent)", error) }
        }
    }

    func stop(_ bottle: Bottle) {
        activity[bottle.name] = "Stopping…"
        Task {
            defer { activity[bottle.name] = nil }
            do { try await sessions.stop(bottle) } catch { fail("Couldn't stop the bottle", error) }
        }
    }

    func installSteam(into bottle: Bottle) {
        activity[bottle.name] = "Installing Steam…"
        let installer = SteamInstaller(launcher: Launcher(paths: paths))
        Task {
            defer { activity[bottle.name] = nil }
            do { try await installer.install(into: bottle) } catch { fail("Couldn't install Steam", error) }
        }
    }

    func launchSteam(in bottle: Bottle, debug: Bool = false) {
        run(bottle, executable: SteamLibrary.defaultExecutableInBottle, debug: debug)
    }

    // MARK: - Finder

    func reveal(_ url: URL, missingHint: String) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            alert = AlertInfo(title: "Nothing to show yet", message: missingHint)
            return
        }
        NSWorkspace.shared.open(url)
    }
}
