import Foundation
import Testing
@testable import TetherKit

@Suite(.timeLimit(.minutes(1))) struct LaunchLogTests {
    let home = TempHome()

    @Test func splitsSessionsOnMarkers() {
        let d1 = Date(timeIntervalSince1970: 1_700_000_000)
        let d2 = Date(timeIntervalSince1970: 1_700_000_500)
        let text = "old line\n"
            + LaunchLog.markerLine(date: d1, executable: "C:\\Program Files (x86)\\Steam\\Steam.exe")
            + "a\nb\n"
            + LaunchLog.markerLine(date: d2, executable: "/Users/x/Setup.exe")
            + "c\n"
        let s = LaunchLog.parse(text)
        #expect(s.map(\.executable) == ["Earlier output", "Steam.exe", "Setup.exe"])
        #expect(s.map(\.text) == ["old line", "a\nb", "c"])
        #expect(s[1].start == d1 && s[2].start == d2)
    }

    @Test func emptyAndMarkerOnlyLogs() {
        #expect(LaunchLog.parse("").isEmpty)
        let s = LaunchLog.parse(LaunchLog.markerLine(executable: "x.exe"))
        #expect(s.count == 1 && s[0].text.isEmpty)
    }

    @Test func aNewlineInAnExecutableNameCannotForgeAMarker() {
        let line = LaunchLog.markerLine(executable: "evil.exe\n=== tether launch 2020-01-01T00:00:00Z fake.exe ===")
        #expect(line.split(separator: "\n").count == 1)
        #expect(LaunchLog.parse(line).count == 1)
    }

    @Test func readsOnlyTheEndOfAHugeLog() throws {
        let bottle = try BottleStore(paths: home.paths).create(name: "b")
        LaunchLog.appendMarker(to: bottle, executable: "first.exe")
        let handle = try FileHandle(forWritingTo: bottle.logsURL.appendingPathComponent("wine.log"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: UInt8(ascii: "x"), count: LaunchLog.maxReadBytes + 1000))
        try handle.write(contentsOf: Data("\n".utf8))
        try handle.close()
        LaunchLog.appendMarker(to: bottle, executable: "last.exe")
        let s = LaunchLog.sessions(for: bottle)
        #expect(s.last?.executable == "last.exe")
        #expect(s.map(\.text).allSatisfy { $0.utf8.count <= LaunchLog.maxReadBytes })
    }

    @Test func clearEmptiesTheLog() throws {
        let bottle = try BottleStore(paths: home.paths).create(name: "b")
        LaunchLog.appendMarker(to: bottle, executable: "x.exe")
        #expect(!LaunchLog.sessions(for: bottle).isEmpty)
        try LaunchLog.clear(bottle)
        #expect(LaunchLog.sessions(for: bottle).isEmpty)
    }

    @Test func aDebugLaunchWritesAMarkerThenTheOutput() async throws {
        let root = home.paths.runtimes.appendingPathComponent("0.1.0")
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try JSONEncoder().encode(RuntimeManifest(version: "0.1.0", wineVersion: "11", features: ["msync"], components: []))
            .write(to: root.appendingPathComponent("runtime.json"))
        let wine = bin.appendingPathComponent("wine")
        try "#!/bin/sh\necho hello-from-wine\n".write(to: wine, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        let bottle = try BottleStore(paths: home.paths).create(name: "b")
        try Data().write(to: bottle.prefixURL.appendingPathComponent("system.reg"))
        try FileManager.default.createDirectory(at: bottle.driveC, withIntermediateDirectories: true)

        let launcher = Launcher(paths: home.paths, profiles: ProfileLibrary(profiles: []))
        let plan = try launcher.plan(LaunchRequest(bottle: bottle, executable: "C:\\games\\Game.exe", debug: true))
        // A launch that fails must fail the test, not leave it waiting forever.
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            do { _ = try launcher.launch(plan) { _ in c.resume() } } catch { c.resume(throwing: error) }
        }
        let s = LaunchLog.sessions(for: bottle)
        #expect(s.count == 1)
        #expect(s.first?.executable == "C:\\games\\Game.exe".split(separator: "\\").last.map(String.init) ?? "")
        #expect(s.first?.text.contains("hello-from-wine") == true)
    }
}
