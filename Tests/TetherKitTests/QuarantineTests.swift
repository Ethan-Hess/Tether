import Foundation
import Testing
@testable import TetherKit

@Suite struct QuarantineTests {
    let home = TempHome()

    private func makeRuntime(version: String = "0.1.0") throws -> WineRuntime {
        let root = home.paths.runtimes.appendingPathComponent(version)
        let exe = root.appendingPathComponent("lib/wine/aarch64-unix/wine.app/Contents/MacOS/wine")
        try FileManager.default.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "x".write(to: exe, atomically: true, encoding: .utf8)
        let manifest = RuntimeManifest(version: version, wineVersion: "11.19", features: [], components: [])
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("runtime.json"))
        return WineRuntime(root: root, manifest: manifest)
    }

    private func quarantine(_ url: URL) {
        let value = Array("0081;6aed4c40;Safari;00000000-0000-0000-0000-000000000000".utf8)
        _ = setxattr(url.path, Quarantine.attribute, value, value.count, 0, 0)
    }

    @Test func detectsTheAttributeOnAFile() throws {
        try FileManager.default.createDirectory(at: home.root, withIntermediateDirectories: true)
        let file = home.root.appendingPathComponent("f")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        #expect(!Quarantine.isQuarantined(file))
        quarantine(file)
        #expect(Quarantine.isQuarantined(file))
        #expect(!Quarantine.isQuarantined(home.root.appendingPathComponent("missing")))
    }

    @Test func runtimeIsQuarantinedWhenItsLoaderIs() throws {
        let runtime = try makeRuntime()
        #expect(!Quarantine.isQuarantined(runtime))
        quarantine(runtime.loaderApp)
        #expect(Quarantine.isQuarantined(runtime))
    }

    @Test func doctorFlagsAQuarantinedRuntimeAndPassesACleanOne() throws {
        let runtime = try makeRuntime()
        func item(_ check: SystemCheck) -> SystemCheck.Item? { check.items.first { $0.name == "Runtime not quarantined" } }

        #expect(item(SystemCheck.run(paths: home.paths))?.ok == true)
        quarantine(runtime.loaderApp)
        let flagged = item(SystemCheck.run(paths: home.paths))
        #expect(flagged?.ok == false)
        #expect(flagged?.detail.contains("0.1.0") == true)
    }

    @Test func noRuntimeMeansNoQuarantineItem() {
        #expect(SystemCheck.run(paths: home.paths).items.contains { $0.name == "Runtime not quarantined" } == false)
    }
}
