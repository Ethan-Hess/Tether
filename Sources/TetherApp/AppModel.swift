import AppKit
import Observation
import SwiftUI
import TetherKit

struct AlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct GameKey: Hashable {
    let bottle: String
    let appID: Int
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
    let settingsStore: SettingsStore
    let artworkStore: SteamArtwork
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
    var settings: AppSettings
    /// Installed Steam games per bottle name; nil until the first read.
    var steamApps: [String: [SteamApp]] = [:]
    /// Cached header image per Steam app ID.
    var artwork: [Int: URL] = [:]
    /// Launching/running state of each Steam game Tether has started or noticed running.
    var gamePhases: [GameKey: GamePhase] = [:]
    private var gameTrackers: [GameKey: GameLaunchTracker] = [:]
    private var gameMonitors: [GameKey: Task<Void, Never>] = [:]
    /// Size of Steam's game-process log when each launch began.
    private var launchOffsets: [GameKey: UInt64] = [:]
    /// Per bottle: the size of Steam's game log when running games were last looked for. If it
    /// hasn't changed, there is nothing new to find.
    private var adoptSeenSizes: [String: UInt64] = [:]
    /// Bumped whenever a bottle starts or stops, so views can re-read state.
    var runStateVersion = 0

    init(paths: TetherPaths = .default) {
        self.paths = paths
        store = BottleStore(paths: paths)
        sessions = BottleSessions(launcher: Launcher(paths: paths))
        profiles = ProfileLibrary.load(paths: paths)
        settingsStore = SettingsStore(paths: paths)
        settings = settingsStore.load()
        artworkStore = SteamArtwork(paths: paths)
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
        runStateVersion += 1
    }

    // MARK: - settings

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        change(&settings)
        do { try settingsStore.save(settings) } catch { fail("Couldn't save settings", error) }
    }

    // MARK: - Steam library

    /// Reads the bottle's installed games, then fetches any missing artwork.
    func loadLibrary(_ bottle: Bottle) async {
        // Steam's support software (redistributables, runtimes) isn't playable, so it's left out.
        let apps = await Task.detached { SteamLibrary.installedApps(in: bottle).filter { !$0.isTool } }.value
        steamApps[bottle.name] = apps
        let store = artworkStore
        for app in apps where artwork[app.appID] == nil {
            if let url = await store.fetch(appID: app.appID) { artwork[app.appID] = url }
        }
    }

    // MARK: - game launch state

    func phase(of app: SteamApp, in bottle: Bottle) -> GamePhase {
        gamePhases[GameKey(bottle: bottle.name, appID: app.appID)] ?? .idle
    }

    /// The game in this bottle that is launching or running, if any.
    func activeGame(in bottle: Bottle) -> SteamApp? {
        steamApps[bottle.name]?.first { phase(of: $0, in: bottle) != .idle }
    }

    /// Asks Steam to start a game (the same request as `tether steam launch`) and follows it:
    /// Launching until Steam reports the game running, Running until Steam reports it gone.
    /// Steam's own game-process log is the source, keyed by app ID.
    func launchGame(in bottle: Bottle, app: SteamApp, debug: Bool = false) {
        guard let url = SteamLibrary.runGameURL(appID: app.appID) else { return }
        let key = GameKey(bottle: bottle.name, appID: app.appID)
        guard phase(of: app, in: bottle) == .idle, activeGame(in: bottle) == nil else { return }
        var tracker = GameLaunchTracker()
        tracker.begin()
        gameTrackers[key] = tracker
        gamePhases[key] = .launching
        launchOffsets[key] = SteamGameProcessLog.size(for: bottle)
        startMonitor(key, bottle: bottle, app: app)
        run(bottle, executable: SteamLibrary.defaultExecutableInBottle, arguments: [url], debug: debug) { [weak self] in
            self?.stopTracking(key)
        }
    }

    /// Ends the game's processes with Wine's `taskkill`, inside this bottle and by the Windows
    /// PIDs Steam is tracking. Steam and the rest of the bottle keep running.
    func stopGame(in bottle: Bottle, app: SteamApp) {
        let appID = app.appID
        // The bottle's profile and extra arguments are meant for games, not for taskkill.
        var plain = bottle
        plain.config.profileID = nil
        plain.config.launchArguments = []
        let launcher = Launcher(paths: paths)
        Task {
            let pids = await Task.detached { SteamGameProcessLog.tracked(for: bottle)[appID] ?? [] }.value
            guard !pids.isEmpty else { return }
            let arguments = ["/F"] + pids.sorted().flatMap { ["/PID", String($0)] }
            do {
                try await Task.detached {
                    let plan = try launcher.plan(LaunchRequest(bottle: plain, executable: "taskkill.exe", arguments: arguments))
                    try launcher.launch(plan)
                }.value
            } catch { fail("Couldn't stop \(app.name)", error) }
        }
    }

    /// Notices games that are already running (started from Steam's own window, or before Tether
    /// was opened) so their cards show Running instead of Play.
    func adoptRunningGames(in bottle: Bottle) async {
        let apps = (steamApps[bottle.name] ?? []).filter { phase(of: $0, in: bottle) == .idle }
        guard !apps.isEmpty else { return }
        let ids = Set(apps.map(\.appID))
        let seen = adoptSeenSizes[bottle.name]
        let result = await Task.detached { () -> (running: Set<Int>, size: UInt64) in
            let size = SteamGameProcessLog.size(for: bottle)
            if seen == size { return ([], size) } // Steam hasn't written anything since the last look
            let live = SteamGameProcessLog.tracked(for: bottle).keys.filter { ids.contains($0) }
            guard !live.isEmpty else { return ([], size) }
            // A log left behind by a Steam that crashed would otherwise look like a running game.
            guard SteamClientProcess.isRunning(in: ProcessList.snapshot()) else { return ([], size) }
            return (Set(live), size)
        }.value
        adoptSeenSizes[bottle.name] = result.size
        let running = result.running
        for app in apps where running.contains(app.appID) {
            let key = GameKey(bottle: bottle.name, appID: app.appID)
            guard phase(of: app, in: bottle) == .idle else { continue }
            var tracker = GameLaunchTracker()
            tracker.adoptRunning()
            gameTrackers[key] = tracker
            gamePhases[key] = .running
            startMonitor(key, bottle: bottle, app: app)
        }
    }

    private func stopTracking(_ key: GameKey) {
        gameMonitors[key]?.cancel()
        gameMonitors[key] = nil
        gameTrackers[key] = nil
        gamePhases[key] = nil
        launchOffsets[key] = nil
    }

    /// Follows one game without polling. It wakes when Steam writes its game log or the Steam
    /// process exits, and otherwise only at the next deadline (a launch timing out, or a slow
    /// heartbeat while running). The process list is read only when the answer matters.
    private func startMonitor(_ key: GameKey, bottle: Bottle, app: SteamApp) {
        gameMonitors[key]?.cancel()
        let appID = app.appID
        gameMonitors[key] = Task { [weak self] in
            let wake = WakeSignal()
            let logWatcher = FileChangeWatcher(url: SteamGameProcessLog.url(for: bottle)) { wake.signal() }
            var steamPID: Int32?
            var exitWatcher: ProcessExitWatcher?
            var reader: SteamGameProcessLog.Reader?
            let startOffset = await self?.launchOffsets[key] // nil: already running, read the session
            defer { logWatcher.cancel(); exitWatcher?.cancel() }

            while !Task.isCancelled {
                guard let self, let tracker = self.gameTrackers[key] else { return }
                // Only the bytes Steam wrote since the last look are read. A launch starts from where
                // the log ended at the click (so an older game can't count); an already-running
                // game is read from the current Steam session.
                let previous = reader
                let advanced = await Task.detached { () -> (reader: SteamGameProcessLog.Reader, running: Bool) in
                    var r = previous ?? SteamGameProcessLog.Reader(bottle: bottle, startingAt: startOffset)
                    if previous != nil { r.advance(bottle) }
                    return (r, !(r.tracked[appID] ?? []).isEmpty)
                }.value
                reader = advanced.reader
                let loggedRunning = advanced.running

                var steamAlive = true
                if tracker.wantsSteamLiveness(gameRunning: loggedRunning) {
                    let known = steamPID
                    let found = await Task.detached { () -> (alive: Bool, pid: Int32?) in
                        if let known, ProcessExitWatcher.isAlive(known) { return (true, known) }
                        let pids = SteamClientProcess.pids(in: ProcessList.snapshot())
                        return (!pids.isEmpty, pids.first)
                    }.value
                    steamAlive = found.alive
                    if found.pid != steamPID {
                        exitWatcher?.cancel()
                        exitWatcher = found.pid.map { ProcessExitWatcher(pid: $0) { wake.signal() } }
                        steamPID = found.pid
                    }
                }
                guard !Task.isCancelled, var current = self.gameTrackers[key] else { return }
                let failure = current.update(gameRunning: loggedRunning && steamAlive, steamRunning: steamAlive)
                if current.phase == .idle {
                    self.stopTracking(key)
                    if let failure { self.gameDidNotStart(app, failure) }
                    return
                }
                self.gameTrackers[key] = current
                self.gamePhases[key] = current.phase

                // If the log couldn't be watched (it doesn't exist yet), look every couple of seconds.
                var wait = current.nextCheck()
                if !logWatcher.isWatching { wait = min(wait ?? 2, 2) }
                await wake.next(timeout: wait)
            }
        }
    }

    private func gameDidNotStart(_ app: SteamApp, _ failure: GameLaunchTracker.Failure) {
        let why: String
        switch failure {
        case .steamClosed: why = "Steam closed before \(app.name) started."
        case .timedOut: why = "\(app.name) didn't start within 3 minutes."
        }
        alert = AlertInfo(title: "\(app.name) didn't start", message: why + " Steam may be waiting for you to log in or update the game. Check the Logs tab (turn on \"Log Wine output\" first) for details.")
    }

    // MARK: - diagnostics

    func diagnostics(for bottle: Bottle, sessions: [LaunchLog.Session]) -> String {
        let runtime = try? RuntimeStore(paths: paths).resolve(version: bottle.config.runtimeVersion)
        return DiagnosticsReport.make(bottle: bottle, runtime: runtime, system: system, sessions: sessions)
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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

    func run(_ bottle: Bottle, executable: String, arguments: [String] = [], debug: Bool = false, onFailure: (() -> Void)? = nil) {
        activity[bottle.name] = "Starting…"
        Task {
            defer { activity[bottle.name] = nil }
            do {
                let plan = try await sessions.start(
                    LaunchRequest(bottle: bottle, executable: executable, arguments: arguments, debug: debug)
                )
                notices[bottle.name] = LaunchNotices.messages(for: plan)
            } catch {
                onFailure?()
                fail("Couldn't start \(URL(fileURLWithPath: executable).lastPathComponent)", error)
            }
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
