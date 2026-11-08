import Foundation
import Testing
@testable import TetherKit

@Suite struct BottleSessionsTests {
    let home = TempHome()

    /// A runtime whose `wine` is a shell script that runs `body`, and a bottle whose prefix is
    /// already initialised (so no wineboot).
    private func fixture(wineBody: String) throws -> (Launcher, Bottle) {
        let root = home.paths.runtimes.appendingPathComponent("0.1.0")
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let manifest = RuntimeManifest(version: "0.1.0", wineVersion: "11.20", features: ["msync"], components: [])
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("runtime.json"))
        for (name, body) in [("wine", wineBody), ("wineserver", "exit 0")] {
            let url = bin.appendingPathComponent(name)
            try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        let bottle = try BottleStore(paths: home.paths).create(name: "b")
        try Data().write(to: bottle.prefixURL.appendingPathComponent("system.reg"))
        try FileManager.default.createDirectory(at: bottle.driveC, withIntermediateDirectories: true)
        return (Launcher(paths: home.paths, profiles: ProfileLibrary(profiles: [])), bottle)
    }

    private func waitUntil(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return false
    }

    @Test func tracksRunningAndExitStatus() async throws {
        let (launcher, bottle) = try fixture(wineBody: "sleep 0.4; exit 3")
        let sessions = BottleSessions(launcher: launcher)
        #expect(await sessions.isRunning("b") == false)

        try await sessions.start(LaunchRequest(bottle: bottle, executable: "C:\\x.exe"))
        #expect(await sessions.isRunning("b"))
        #expect(await sessions.runningBottles() == ["b"])

        #expect(await waitUntil { await !sessions.isRunning("b") })
        #expect(await sessions.lastExitStatus("b") == 3)
    }

    @Test func aFailedStartIsNotLeftRunning() async throws {
        let (launcher, bottle) = try fixture(wineBody: "exit 0")
        try FileManager.default.removeItem(at: home.paths.runtimes) // plan() will fail
        let sessions = BottleSessions(launcher: launcher)
        await #expect(throws: (any Error).self) {
            try await sessions.start(LaunchRequest(bottle: bottle, executable: "C:\\x.exe"))
        }
        #expect(await sessions.isRunning("b") == false)
    }

    @Test func stopRunsWineserverKill() async throws {
        let (launcher, bottle) = try fixture(wineBody: "exit 0")
        try await BottleSessions(launcher: launcher).stop(bottle)
    }

    @Test func observerHearsStartAndFinish() async throws {
        let (launcher, bottle) = try fixture(wineBody: "exit 0")
        let sessions = BottleSessions(launcher: launcher)
        let count = Counter()
        await sessions.setObserver { count.increment() }
        try await sessions.start(LaunchRequest(bottle: bottle, executable: "C:\\x.exe"))
        #expect(await waitUntil { count.value >= 2 })
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}
