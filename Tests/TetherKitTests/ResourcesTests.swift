import Foundation
import Testing
@testable import TetherKit

@Suite struct ResourcesTests {
    let home = TempHome()

    private func makeFile(_ relative: String) throws -> URL {
        let url = home.root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
        return url
    }

    @Test func appResourcesWinOverTheFallback() throws {
        let inApp = try makeFile("Resources/Runtimes/catalog.json")
        let other = home.root.appendingPathComponent("elsewhere/catalog.json")
        let found = TetherResources.url(forResource: "catalog", withExtension: "json", subdirectory: "Runtimes", mainResources: home.root.appendingPathComponent("Resources")) { other }
        #expect(found == inApp)
    }

    @Test func fallsBackWhenTheAppHasNoSuchResource() throws {
        let fallback = home.root.appendingPathComponent("fallback.json")
        let found = TetherResources.url(forResource: "catalog", withExtension: "json", subdirectory: "Runtimes", mainResources: home.root.appendingPathComponent("Resources")) { fallback }
        #expect(found == fallback)
    }

    @Test func outsideAnAppOnlyTheFallbackIsUsed() {
        let fallback = home.root.appendingPathComponent("fallback.json")
        #expect(TetherResources.url(forResource: "x", mainResources: nil) { fallback } == fallback)
        #expect(TetherResources.url(forResource: "x", mainResources: nil) == nil)
    }

    @Test func findsAFolderResourceWithoutAnExtension() throws {
        _ = try makeFile("Resources/Profiles/a.json")
        let url = TetherResources.url(forResource: "Profiles", mainResources: home.root.appendingPathComponent("Resources"))
        #expect(url?.lastPathComponent == "Profiles")
    }

    @Test func theBundledCatalogAndProfilesStillLoadInDevelopment() {
        #expect(RuntimeCatalog.bundled().source(version: nil) != nil)
        #expect(ProfileLibrary.load(paths: home.paths).profile(id: "steam") != nil)
    }
}
