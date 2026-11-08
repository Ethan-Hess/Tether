import Foundation
import Testing
@testable import TetherKit

@Suite struct SteamInstallerTests {
    let home = TempHome()

    @Test func refusesNonHTTPSSources() async throws {
        let bottle = try BottleStore(paths: home.paths).create(name: "s")
        let installer = SteamInstaller(
            launcher: Launcher(paths: home.paths, profiles: ProfileLibrary(profiles: [])),
            source: URL(string: "http://example.com/SteamSetup.exe")!,
            download: { _ in Issue.record("must not download"); throw URLError(.badURL) }
        )
        await #expect(throws: SteamInstallError.unsupportedURL("http://example.com/SteamSetup.exe")) {
            try await installer.install(into: bottle)
        }
    }

    @Test func officialSourceIsHTTPSOnValveCDN() {
        #expect(SteamInstaller.installerURL.scheme == "https")
        #expect(SteamInstaller.installerURL.host == "cdn.cloudflare.steamstatic.com")
    }

    @Test func reportsInstalledOnlyWhenSteamExeExists() throws {
        let bottle = try BottleStore(paths: home.paths).create(name: "s")
        #expect(!SteamInstaller.isInstalled(in: bottle))
        let dir = bottle.driveC.appendingPathComponent(SteamLibrary.defaultRootInBottle, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data().write(to: dir.appendingPathComponent("Steam.exe"))
        #expect(SteamInstaller.isInstalled(in: bottle))
    }
}
