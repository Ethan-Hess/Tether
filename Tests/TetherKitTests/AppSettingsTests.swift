import Foundation
import Testing
@testable import TetherKit

@Suite struct AppSettingsTests {
    let home = TempHome()
    var store: SettingsStore { SettingsStore(paths: home.paths) }

    @Test func missingFileGivesDefaults() {
        #expect(store.load() == AppSettings())
    }

    @Test func roundTrips() throws {
        let s = AppSettings(defaultBackend: .dxvk, defaultWindowsVersion: .win11, defaultShowPerformanceHUD: true, debugLoggingByDefault: true)
        try store.save(s)
        #expect(store.load() == s)
    }

    @Test func corruptFileGivesDefaults() throws {
        try FileManager.default.createDirectory(at: home.paths.root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: home.paths.settings)
        #expect(store.load() == AppSettings())
    }

    @Test func unknownValuesAndKeysDoNotDiscardTheRest() throws {
        try FileManager.default.createDirectory(at: home.paths.root, withIntermediateDirectories: true)
        let json = #"{"defaultBackend":"from-the-future","defaultWindowsVersion":"win11","somethingNew":1,"debugLoggingByDefault":true}"#
        try Data(json.utf8).write(to: home.paths.settings)
        let s = store.load()
        #expect(s.defaultBackend == nil)
        #expect(s.defaultWindowsVersion == .win11)
        #expect(s.debugLoggingByDefault)
    }

    @Test func newBottleConfigUsesTheDefaults() {
        let c = AppSettings(defaultBackend: .dxmt, defaultWindowsVersion: .win81, defaultShowPerformanceHUD: true).newBottleConfig(profileID: "steam")
        #expect(c.backend == .dxmt && c.windowsVersion == .win81 && c.showPerformanceHUD && c.profileID == "steam")
    }

    @Test func diskUsageCountsFilesBelowAFolder() throws {
        let dir = home.root.appendingPathComponent("d", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100_000).write(to: dir.appendingPathComponent("sub/a"))
        try Data(repeating: 1, count: 100_000).write(to: dir.appendingPathComponent("b"))
        #expect(DiskUsage.size(of: dir) >= 200_000)
        #expect(DiskUsage.size(of: home.root.appendingPathComponent("nope")) == 0)
    }
}
