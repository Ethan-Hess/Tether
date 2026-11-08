import Foundation
import Testing
@testable import TetherKit

@Suite struct WatchersTests {
    let home = TempHome()

    private func file(_ name: String = "log.txt") throws -> URL {
        try FileManager.default.createDirectory(at: home.root, withIntermediateDirectories: true)
        let url = home.root.appendingPathComponent(name)
        try Data("start\n".utf8).write(to: url)
        return url
    }

    private func append(_ text: String, to url: URL) throws {
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        try h.write(contentsOf: Data(text.utf8))
        try h.close()
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<120 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return false
    }

    @Test func fileWatcherFiresOnAppendAndStopsWhenCancelled() async throws {
        let url = try file()
        let count = Counter()
        let watcher = FileChangeWatcher(url: url) { count.increment() }
        #expect(await eventually { watcher.isWatching })
        let before = count.value
        try append("more\n", to: url)
        #expect(await eventually { count.value > before })
        watcher.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)
        let after = count.value
        try append("ignored\n", to: url)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(count.value == after, "a cancelled watcher must stay quiet")
        #expect(!watcher.isWatching)
    }

    @Test func fileWatcherAttachesWhenTheFileAppearsLater() async throws {
        try FileManager.default.createDirectory(at: home.root, withIntermediateDirectories: true)
        let url = home.root.appendingPathComponent("later.txt")
        let count = Counter()
        let watcher = FileChangeWatcher(url: url) { count.increment() }
        defer { watcher.cancel() }
        #expect(!watcher.isWatching)
        try Data("hi\n".utf8).write(to: url)
        #expect(await eventually { watcher.isWatching }, "it should pick the file up within a couple of seconds")
    }

    @Test func fileWatcherSurvivesTheFileBeingReplaced() async throws {
        let url = try file()
        let count = Counter()
        let watcher = FileChangeWatcher(url: url) { count.increment() }
        defer { watcher.cancel() }
        #expect(await eventually { watcher.isWatching })
        try FileManager.default.removeItem(at: url)
        try Data("new\n".utf8).write(to: url)
        #expect(await eventually { watcher.isWatching && count.value >= 2 })
        let before = count.value
        try append("after\n", to: url)
        #expect(await eventually { count.value > before }, "writes to the replacement file must be seen")
    }

    @Test func processExitWatcherFiresWhenTheProcessEnds() async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["0.3"]
        try p.run()
        #expect(ProcessExitWatcher.isAlive(p.processIdentifier))
        let count = Counter()
        let watcher = ProcessExitWatcher(pid: p.processIdentifier) { count.increment() }
        defer { watcher.cancel() }
        #expect(await eventually { count.value >= 1 })
        p.waitUntilExit()
        #expect(!ProcessExitWatcher.isAlive(p.processIdentifier))
    }

    @Test func wakeSignalCoalescesAndTimesOut() async {
        let wake = WakeSignal()
        wake.signal(); wake.signal(); wake.signal()
        await wake.next() // returns at once: three signals are one
        let start = Date()
        await wake.next(timeout: 0.2) // nothing pending, so it waits for the timeout
        let waited = Date().timeIntervalSince(start)
        #expect(waited >= 0.15 && waited < 1.5)
    }

    // MARK: tracker deadlines

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func livenessIsOnlyAskedWhenItMatters() {
        var t = GameLaunchTracker()
        #expect(!t.wantsSteamLiveness(gameRunning: false, now: t0))
        t.begin(now: t0)
        #expect(!t.wantsSteamLiveness(gameRunning: false, now: t0 + 5), "no need to look at processes early in a launch")
        #expect(!t.wantsSteamLiveness(gameRunning: true, now: t0 + 30))
        #expect(t.wantsSteamLiveness(gameRunning: false, now: t0 + 25), "after the grace period it decides whether Steam is gone")
        t.update(gameRunning: true, steamRunning: true, now: t0 + 10)
        #expect(t.wantsSteamLiveness(gameRunning: true, now: t0 + 11), "a running game's log is only trusted while Steam is alive")
    }

    @Test func nextCheckIsDeadlineWhileLaunchingHeartbeatWhileRunningNilWhenIdle() {
        var t = GameLaunchTracker()
        #expect(t.nextCheck(now: t0) == nil)
        t.begin(now: t0)
        #expect(abs(t.nextCheck(now: t0)! - 20.5) < 0.01)
        #expect(abs(t.nextCheck(now: t0 + 21)! - 159.5) < 0.01)
        t.update(gameRunning: true, steamRunning: true, now: t0 + 22)
        #expect(t.nextCheck(now: t0 + 22) == GameLaunchTracker.heartbeat)
        t.cancel()
        #expect(t.nextCheck(now: t0) == nil)
    }
}
