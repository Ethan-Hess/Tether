import Foundation

/// Tracks the Wine processes Tether started per bottle, so a UI can show Running/Stopped.
///
/// Only processes started through this object are counted. A game that Steam launches runs
/// under Steam's own process, so "running" means "something Tether launched is still alive";
/// `stop` stops everything in the bottle regardless (`wineserver -k`).
public actor BottleSessions {
    private let launcher: Launcher
    private var running: [String: Set<UUID>] = [:]
    private var exits: [String: Int32] = [:]
    private var observer: (@Sendable () -> Void)?

    public init(launcher: Launcher = Launcher()) {
        self.launcher = launcher
    }

    /// Called (on the actor) whenever a bottle's running state changes.
    public func setObserver(_ observer: (@Sendable () -> Void)?) {
        self.observer = observer
    }

    public func isRunning(_ name: String) -> Bool {
        !(running[name] ?? []).isEmpty
    }

    public func runningBottles() -> Set<String> {
        Set(running.filter { !$0.value.isEmpty }.keys)
    }

    /// Exit status of the most recent process that ended in this bottle.
    public func lastExitStatus(_ name: String) -> Int32? { exits[name] }

    /// Plans and starts a process. Preparing the prefix on first run blocks for a while, so the
    /// work runs off the actor. Returns the plan so the caller can show its notices.
    @discardableResult
    public func start(_ request: LaunchRequest) async throws -> LaunchPlan {
        let name = request.bottle.name
        let token = UUID()
        let launcher = self.launcher
        // Registered before launching so an immediate exit can't be reported first.
        running[name, default: []].insert(token)
        exits[name] = nil
        changed()
        do {
            return try await Task.detached {
                let plan = try launcher.plan(request)
                try launcher.launch(plan) { [weak self] status in
                    guard let self else { return }
                    Task { await self.finished(name, token, status: status) }
                }
                return plan
            }.value
        } catch {
            finished(name, token, status: nil)
            throw error
        }
    }

    /// Stops every process in the bottle.
    public func stop(_ bottle: Bottle) async throws {
        let launcher = self.launcher
        try await Task.detached { try launcher.shutdown(bottle) }.value
    }

    private func finished(_ name: String, _ token: UUID, status: Int32?) {
        running[name]?.remove(token)
        if running[name]?.isEmpty == true { running[name] = nil }
        if let status { exits[name] = status }
        changed()
    }

    private func changed() { observer?() }
}
