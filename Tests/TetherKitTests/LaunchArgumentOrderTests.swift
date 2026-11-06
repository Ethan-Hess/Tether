import Foundation
import Testing
@testable import TetherKit

@Suite struct LaunchArgumentOrderTests {
    let home = TempHome()

    private func installRuntime(features: [String] = ["msync"]) throws {
        let root = home.paths.runtimes.appendingPathComponent("0.1.0")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manifest = RuntimeManifest(version: "0.1.0", wineVersion: "11.20", features: features, components: [])
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("runtime.json"))
    }

    private func bottle(_ name: String = "b", args: [String] = [], profileID: String? = nil) throws -> Bottle {
        try BottleStore(paths: home.paths).create(name: name, config: BottleConfig(profileID: profileID, launchArguments: args))
    }

    private let game = GameProfile(
        id: "game", name: "Game", executables: ["game.exe"], steamAppIDs: [5], launchArguments: ["-game"]
    )

    // MARK: bottle.json

    @Test func bottleFilesWithoutLaunchArgumentsStillDecode() throws {
        let store = BottleStore(paths: home.paths)
        let created = try store.create(name: "old")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: created.configURL)) as! [String: Any]
        json.removeValue(forKey: "launchArguments")
        try JSONSerialization.data(withJSONObject: json).write(to: created.configURL)
        #expect(try store.load(name: "old").config.launchArguments == [])
    }

    @Test func launchArgumentsRoundTrip() throws {
        let store = BottleStore(paths: home.paths)
        var b = try store.create(name: "rt")
        b.config.launchArguments = ["-silent", "-x"]
        try store.save(b)
        #expect(try store.load(name: "rt").config.launchArguments == ["-silent", "-x"])
    }

    // MARK: ordering and matching

    @Test func orderIsProfileThenBottleThenCommandLine() throws {
        try installRuntime()
        let launcher = Launcher(paths: home.paths, profiles: ProfileLibrary(profiles: [game]))
        let plan = try launcher.plan(LaunchRequest(bottle: try bottle(args: ["-bottle"]), executable: "C:\\g\\Game.exe", arguments: ["-cli"]))
        #expect(plan.arguments == ["C:\\g\\Game.exe", "-game", "-bottle", "-cli"])
    }

    @Test func aProfileMatchedOnlyByAppIDContributesNoArguments() throws {
        try installRuntime()
        let launcher = Launcher(paths: home.paths, profiles: ProfileLibrary(profiles: [game]))
        let request = LaunchRequest(bottle: try bottle(args: ["-silent"]), executable: "C:\\Steam\\Steam.exe", arguments: ["steam://rungameid/5"], steamAppID: 5)
        #expect(launcher.resolveProfileMatch(for: request)?.match == .steamAppID)
        let plan = try launcher.plan(request)
        #expect(plan.arguments == ["C:\\Steam\\Steam.exe", "-silent", "steam://rungameid/5"], "the game's -game must not reach Steam.exe")
    }

    @Test func explicitAndExecutableMatchesStillContribute() throws {
        try installRuntime()
        let launcher = Launcher(paths: home.paths, profiles: ProfileLibrary(profiles: [game]))
        let explicit = LaunchRequest(bottle: try bottle("e"), executable: "C:\\x\\other.exe", profileID: "game", steamAppID: 5)
        #expect(launcher.resolveProfileMatch(for: explicit)?.match == .explicit)
        #expect(try launcher.plan(explicit).arguments == ["C:\\x\\other.exe", "-game"])

        let byExe = LaunchRequest(bottle: try bottle("x"), executable: "C:\\x\\GAME.exe")
        #expect(launcher.resolveProfileMatch(for: byExe)?.match == .executable)
        #expect(try launcher.plan(byExe).arguments == ["C:\\x\\GAME.exe", "-game"])
    }

    @Test func bottleArgumentsApplyEvenWithoutAProfile() throws {
        try installRuntime()
        let launcher = Launcher(paths: home.paths, profiles: ProfileLibrary(profiles: []))
        let plan = try launcher.plan(LaunchRequest(bottle: try bottle(args: ["-a"]), executable: "C:\\any.exe"))
        #expect(plan.arguments == ["C:\\any.exe", "-a"])
    }

    // MARK: Steam launch

    @Test func steamLaunchPlanCarriesSteamArgumentsAndTheGamesRule() throws {
        try installRuntime(features: ["msync", "managed-graphics", "compat-rules"])
        let launcher = Launcher(paths: home.paths) // built-in profiles: steam and overwatch
        let url = try #require(SteamLibrary.runGameURL(appID: 2357570))
        let plan = try launcher.plan(LaunchRequest(
            bottle: try bottle(args: ["-silent"]), executable: SteamLibrary.defaultExecutableInBottle, arguments: [url]
        ))
        #expect(plan.arguments == [SteamLibrary.defaultExecutableInBottle, "-cef-disable-gpu", "-silent", url])
        #expect(plan.compatRules.text.contains("exe=steam:2357570;dxgi=dxmt"), "the game's backend rule is in place when Steam starts")
    }
}
