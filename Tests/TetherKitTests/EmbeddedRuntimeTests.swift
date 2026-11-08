import Foundation
import Testing
@testable import TetherKit

@Suite struct EmbeddedRuntimeTests {
    let home = TempHome()
    var embeddedRoot: URL { home.root.appendingPathComponent("App/EmbeddedRuntimes") }

    private func add(_ version: String, under root: URL, features: [String] = []) throws {
        let dir = root.appendingPathComponent(version)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = RuntimeManifest(version: version, wineVersion: "11", features: features, components: [])
        try JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("runtime.json"))
    }

    private func store(embedded: Bool = true) -> RuntimeStore {
        RuntimeStore(paths: home.paths, embeddedRoot: embedded ? embeddedRoot : nil)
    }

    @Test func listsEmbeddedAndInstalledTogether() throws {
        try add("0.1.0", under: home.paths.runtimes)
        try add("0.2.0", under: embeddedRoot)
        let all = store().list()
        #expect(all.map(\.version) == ["0.1.0", "0.2.0"])
        #expect(all.map(\.isEmbedded) == [false, true])
    }

    @Test func theEmbeddedCopyWinsForTheSameVersion() throws {
        try add("0.2.0", under: home.paths.runtimes, features: ["installed"])
        try add("0.2.0", under: embeddedRoot, features: ["embedded"])
        let all = store().list()
        #expect(all.count == 1)
        #expect(all[0].isEmbedded && all[0].supports(feature: "embedded"))
    }

    @Test func resolvesTheNewestOrAPinnedVersionAcrossBoth() throws {
        try add("0.1.0", under: home.paths.runtimes)
        try add("0.3.0", under: embeddedRoot)
        try add("0.2.0", under: home.paths.runtimes)
        #expect(try store().resolve(version: nil).version == "0.3.0")
        #expect(try store().resolve(version: "0.1.0").isEmbedded == false)
        #expect(throws: RuntimeStoreError.notFound("9.9")) { try store().resolve(version: "9.9") }
    }

    @Test func aMissingEmbeddedFolderMeansInstalledOnly() throws {
        try add("0.1.0", under: home.paths.runtimes)
        #expect(store().list().map(\.version) == ["0.1.0"])
        #expect(store(embedded: false).list().map(\.version) == ["0.1.0"])
    }

    @Test func nothingAvailableIsAnError() {
        #expect(throws: RuntimeStoreError.noRuntimesInstalled) { try store().resolve(version: nil) }
    }

    @Test func foldersWithoutAManifestAreIgnored() throws {
        try FileManager.default.createDirectory(at: embeddedRoot.appendingPathComponent("junk"), withIntermediateDirectories: true)
        try add("0.2.0", under: embeddedRoot)
        #expect(store().list().map(\.version) == ["0.2.0"])
    }

    private func quarantineLoader(of runtime: WineRuntime) throws {
        try FileManager.default.createDirectory(at: runtime.loaderApp, withIntermediateDirectories: true)
        setxattr(runtime.loaderApp.path, Quarantine.attribute, "0081;00000000;x;", 16, 0, 0)
    }

    @Test func anEmbeddedRuntimeIsNotFlaggedAsQuarantinedButAnInstalledOneIs() throws {
        try add("0.1.0", under: embeddedRoot)
        try quarantineLoader(of: try RuntimeStore(paths: home.paths, embeddedRoot: embeddedRoot).resolve(version: nil))
        let embedded = SystemCheck.run(paths: home.paths, embeddedRoot: embeddedRoot)
        #expect(embedded.items.first { $0.name == "Wine runtime" }?.ok == true)
        #expect(embedded.items.first { $0.name == "Runtime not quarantined" }?.ok == true, "the app's signature covers its own runtime")

        try add("0.2.0", under: home.paths.runtimes)
        try quarantineLoader(of: try RuntimeStore(paths: home.paths, embeddedRoot: nil).resolve(version: "0.2.0"))
        let installed = SystemCheck.run(paths: home.paths, embeddedRoot: embeddedRoot)
        #expect(installed.items.first { $0.name == "Runtime not quarantined" }?.ok == false)
    }
}
